require 'reel'
require 'websocket/driver'

class ReelRouter
  def initialize(routes)    
    @routes = routes
  end

  def self.parse_post_params(env)
    lst = MultiJson.load(env.body.to_s)
    # lst = env.body.to_s.split("\n").map(&:chomp).map{|s| s.split('&') }.flatten.map{|s| s.split('=') }.inject({}){|r, a| r.merge(a.first => a.last) }
    p lst
    lst
  end

  def default
    [ 404, {'Content-Type' => 'text/plain'}, 'not found' ]
  end

  def call(env)
    @routes.each do |route|
      next unless env.method == route[:method]
      match = env.url.match(route[:pattern])
      # match = env['REQUEST_PATH'].match(route[:pattern])
      if match
        return route[:controller].call( env, match )
      end
    end
    default
  end
end

class Web < Reel::Server::HTTP
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize params = {}
    cfg = Center.current.server_config
    host = cfg[:host]
    port = cfg[:port]
    info "server starting on #{host}:#{port}"
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    while request = connection.request
      if request.websocket?
        info "Received a WebSocket connection"

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
    # if request.url == "/"
    #   return render_index(connection)
    # end

    rout = ReelRouter.new(
      [
        # {
        #   method: 'GET',
        #   pattern: %r[^/api/v1/games/(?<id>[0-9A-Za-z-]+)],
        #   controller: lambda {|env, match| game_params(match[:id]) }
        # },
        {
          method: 'GET',
          pattern: %r[^/api/v1/games/(?<id>[0-9A-Za-z-]+)],
          controller: lambda {|env, match| game_params(match[:id]) }
        },
        {
          method: 'GET',
          pattern: %r[^/api/v1/games],
          controller: lambda {|env, match| games_list }
        },
        {
          method: 'POST',
          pattern: %r[^/api/v1/games],
          controller: lambda {|env, match| create_game(ReelRouter.parse_post_params(env)) }
        }
      ]
    )

    # info "404 Not Found: #{request.path}"
    connection.respond *rout.call(request)
    # connection.respond :not_found, "Not found"
  end

  def games_list
    [:ok, 'test it']
  end

  def create_game(params)
    p params
    uuid = Game.build params
    p uuid
    [:ok, {uuid: uuid}.to_json]
  end

  def game_params(id)
    [:ok, 'test it']
  end

  def route_websocket(socket)
    if socket.url =~ /\/player\//
      PlayerConnect.create(socket, socket.url)
    elsif socket.url =~ /\/game\//
      AdminConnect.create(socket, socket.url)
    elsif socket.url == '/swot/control'
      p 'control channel TODO'
      # ClientConnect(socket)
    end
  end
end
