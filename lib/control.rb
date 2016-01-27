require 'march_hare'
class Control
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::IO
  CONTROL_CHANNEL = '/swot/control'
  finalizer :finalizer
  @players = []

  attr_accessor :control_channel
  def initialize params = {}
    info "starting control"
    @conn = MarchHare.connect
    @ch = @conn.create_channel
    @fan = @ch.topic('control', auto_delete: true)
    @fan_channels = @ch.topic('channels', auto_delete: true)
    @control_queue = @ch.queue('swot.control', auto_delete: true).bind(@fan, routing_key: 'swot.controls')
    @channels_queue = @ch.queue('swot.channels', auto_delete: true).bind(@fan_channels, routing_key: 'swot.channels')
    @fan_channels.publish('swot.control', routing_key: 'swot.channels')
    # @sub = ::Redis.new(driver: :celluloid)
    # @redis = ::Redis.new(driver: :celluloid)
    # @channel_name = params[:channel] || CONTROL_CHANNEL
    async.run
    info "start control"
  end

  def add_game(id)
    info 'q gm'
    @fan_game = @ch.topic('game', auto_delete: true)
    @game_queue = @ch.queue("swot.game.#{id}", auto_delete: true).bind(@fan_game, routing_key: "swot.game.#{id}")
    @game_queue.subscribe do |meta, opts, msg|
      p meta.routing_key, msg
      game_id = /swot\.game\.(.+)/.match(meta.routing_key).try(:[], 1)
      if game_id
        game = Actor[:"game_#{game_id}"]
      end
    end
    info 'q gm'
  end

  def games_list
  end

  def game_state(id)
  end

  def player_state(id)
  end

  def pitch
  end

  def pass
  end

  def vote
  end

  def event
  end


  def add_player(id)
    info 'add pl'
    fan_player = @ch.topic("player.#{id}", auto_delete: true)
    player_queue = @ch.queue("player.#{id}", auto_delete: true).bind(fan_player, routing_key: "player.#{id}")
    @state.players["player.#{id}"]
    player_queue.subscribe do |meta, msg|
      p meta.routing_key, msg
    end
  end

  def clear_game(id)
    game = @state.game["game.#{id}"]
    game[:queue].unbind if player[:queue]
    game[:fan].delete
  end

  def clear_player(id)
    player = @state.players["player.#{id}"]
    player[:queue].unbind if player[:queue]
    player[:fan].delete
  end

  def run
    info 'rn'
    
    @control_queue.subscribe do |meta, msg|
      p meta.routing_key, msg
      ch = meta.routing_key
      info "#{ch.inspect} :: #{msg.inspect}"
      sel = begin
              MultiJson.load(msg)
            rescue Exception => e
              {error: e.message}
            end

      info sel.inspect
      unless sel[:error]
        klass = ::Message.parse(ch, sel)
        info klass
        klass.new(ch, sel).process if klass
      end
    end
    # @redis.subscribe(@channel_name, '/game/*', '/player/*') do |on|
    # @sub.psubscribe('/*/*') do |on|
    #   on.pmessage do |pat, ch, msg|
    #   end
    #   on.psubscribe do |ch, subs|
    #     # self.control_channel = on
    #     info "sub #{ch.inspect} -- #{subs.inspect}"
    #     info on.inspect
    #   end
    #   on.punsubscribe do
    #     info 'un'
    #     async.stop
    #   end
    # end
  end

  def stop
    # @sub.punsubscribe
    async.terminate
  end

  def finalizer
    info 'closing control'
    @conn.close
    info "stop control"
  end
end
