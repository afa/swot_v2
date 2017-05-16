class Control
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::IO
  CONTROL_CHANNEL = 'swot.control'.freeze
  finalizer :finalizer
  @players = []

  attr_accessor :control_channel

  def self.current
    Actor[:control]
  end

  def initialize(_params = {})
    async.run
  end

  def publish_control(params)
    info "publish_control #{params.inspect}"
    # @fan.publish(params.to_json, routing_key: 'swot.control.client')
  end

  def add_game(id)
    # state = Actor[:"state_#{id}"]
  end

  def games_list; end

  def game_state(id, params = {}); end

  def player_state(id); end

  def pitch; end

  def pass; end

  def vote; end

  def event; end

  def add_player(game_id, id)
    # game = Actor[:"game_#{game_id}"]
    # state = Actor[:"state_#{game_id}"]
  end

  def clear_game(id)
    # state = Actor[:"state_#{game_id}"]
    # g = state.game
  end

  def clear_player(id)
    # state = Actor[:"state_#{game_id}"]
  end

  def parse_msg(ch, msg)
    info "#{ch.inspect} :: #{msg.inspect}"
    sel = begin
            MultiJson.load(msg)
          rescue StandardError => exc
            { error: exc.message }
          end

    return if sel[:error]
    klass = ::Message.parse(ch, sel)
    klass.new(ch, sel).process if klass
  end

  def run
    info 'rn'
  end

  def stop
    async.terminate
  end

  def finalizer
    info 'closing control'
  end
end
