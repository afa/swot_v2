require 'march_hare'
class Control
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::IO
  CONTROL_CHANNEL = 'swot.control'
  finalizer :finalizer
  @players = []

  attr_accessor :control_channel

  def self.current
    Actor[:control]
  end

  def initialize params = {}
    info "starting control"
    @conn = MarchHare.connect
    @ch = @conn.create_channel
    @ctl = @ch.queue('swot')
    @fan = @ch.topic('control', auto_delete: true)
    @fan_channels = @ch.topic('channels', auto_delete: true)
    @control_queue = @ch.queue('swot.control', exclusive: false, auto_delete: true).bind(@fan, routing_key: 'swot.control')
    @channels_queue = @ch.queue('swot.channels', exclusive: false, auto_delete: true).bind(@fan_channels, routing_key: 'swot.channel')
    # @fan_channels.publish('swot.control', routing_key: 'swot.channels')
    async.run
    info "start control"
  end

  def publish_control params
    info "publish_control #{params.inspect}"
    @fan.publish(params.to_json, routing_key: 'swot.control.client')
  end

  def add_game(id)
    info 'q gm'
    state = Actor[:"state_#{id}"]
    @fan_game = @ch.topic('game', auto_delete: true)
    @game_queue = @ch.queue("swot.game.#{id}", exclusive: false, auto_delete: true).bind(@fan_game, routing_key: "swot.game.#{id}")
    state.game = {queue: @game_queue, fan: @fan_game}
    @game_queue.subscribe do |meta, msg|
      # @ch.ack meta.delivery_tag
      p meta.routing_key, msg
      parse_msg meta.routing_key, msg
      # game_id = /swot\.game\.(.+)/.match(meta.routing_key).try(:[], 1)
      # if game_id
      #   game = Actor[:"game_#{game_id}"]
      # end
    end
    # @fan_channels.publish("game.#{id}", routing_key: 'swot.channels')
    info 'q gm'
  end

  def games_list

  end

  def game_state id, params = {}
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


  def add_player(game_id, id)
    info 'add pl'
    game = Actor[:"game_#{game_id}"]
    state = Actor[:"state_#{game_id}"]
    fan_player = @ch.topic("player.#{id}", auto_delete: true)
    player_queue = @ch.queue("player.#{id}", exclusive: false, auto_delete: true).bind(fan_player, routing_key: "player.#{id}")
    state.player_channels[:"player.#{id}"] = {q: player_queue, x: fan_player}
    player_queue.subscribe do |meta, msg|
      # @ch.ack meta.delivery_tag
      p meta.routing_key, msg
      parse_msg meta.routing_key, msg
    end
  end

  def clear_game(id)
    state = Actor[:"state_#{game_id}"]
    g = state.game
    g[:queue].unbind if g[:queue]
    g[:fan].delete
  end

  def clear_player(id)
    state = Actor[:"state_#{game_id}"]
    player = state.player_channels[:"player.#{id}"]
    player[:queue].unbind if player[:queue]
    player[:fan].delete
  end

  def parse_msg ch, msg
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

  def run
    info 'rn'
    
    @control_queue.subscribe do |meta, msg|
      # @ch.ack meta.delivery_tag
      p meta.routing_key, msg
      parse_msg meta.routing_key, msg
    end
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
