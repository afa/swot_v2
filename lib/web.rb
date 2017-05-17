require 'reel'
require 'websocket/driver'

class ReelRouter
  def initialize(routes)
    @routes = routes
  end

  def self.parse_post_params(env)
    lst = MultiJson.load(env.body.to_s)
    # lst = env.body.to_s.split("\n").map(&:chomp).map{|s| s.split('&') }.flatten.map{|s| s.split('=') }.inject({}){|r, a| r.merge(a.first => a.last) }
    lst
  end

  def default
    [404, { 'Content-Type' => 'text/plain' }, 'not found']
  end

  def call(env)
    @routes.each do |route|
      next unless env.method == route[:method]
      match = env.url.match(route[:pattern])
      # match = env['REQUEST_PATH'].match(route[:pattern])
      return route[:controller].call(env, match) if match
    end
    default
  end
end

class Web < Reel::Server::HTTP
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize(_params = {})
    cfg = Center.current.server_config
    host = cfg[:host]
    port = cfg[:port]
    info "server starting on #{host}:#{port}"
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    while request = connection.request
      if request.websocket?
        # We're going to hand off this connection to another actor (TimeClient)
        # However, initially Reel::Connections are "attached" to the
        # Reel::Server::HTTP actor, meaning that the server manages the connection
        # lifecycle (e.g. error handling) for us.
        #
        # If we want to hand this connection off to another actor, we first
        # need to detach it from the Reel::Server (in this case, Reel::Server::HTTP)
        connection.detach

        route_websocket request.websocket
        return
      else
        route_request connection, request
      end
    end
  end

  def route_request(connection, request)
    rout = ReelRouter.new(
      [
        {
          method: 'GET',
          pattern: %r{^/api/v1/games/(?<id>[0-9A-Za-z-]+)},
          controller: ->(_env, match) { game_params(match[:id]) }
        },
        {
          method: 'GET',
          pattern: %r{^/api/v1/games},
          controller: ->(_env, _match) { games_list }
        },
        {
          method: 'POST',
          pattern: %r{^/api/v1/games},
          controller: ->(env, _match) { create_game(ReelRouter.parse_post_params(env)) }
        }
      ]
    )

    connection.respond(*rout.call(request))
  end

  def games_list
    [:ok, 'test it']
  end

  def game_results(game_id)
    res = Game.results_for(game_id)
    [:ok, res.to_json]
  end

  def create_game(params)
    uuid = Game.build(params)
    [:ok, { uuid: uuid }.to_json]
  end

  def game_params(id)
    game = Store::Game.find(uuid: id).first
    if game
      [:ok, game.as_json_params.to_json]
    else
      [:not_found, { errors: ["Game with id #{id} not found in core"] }.to_json]
    end
  end

  def route_websocket(socket)
    url = socket.url
    if url =~ %r{/player/}
      PlayerConnect.create(socket, url)
    elsif url =~ %r{/game/}
      AdminConnect.create(socket, url)
    elsif url == '/swot/control'
      # ClientConnect(socket)
    end
  end
end
