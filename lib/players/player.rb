class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis, :order

  def initialize params = {}
    # @redis ||= ::Redis.new(driver: :celluloid)
    @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      unless store
        info "player #{params.inspect} started"
        store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state], uuid: params[:uuid], game_uuid: params[:game_uuid])
      end
      @uuid = store.uuid
      @game_uuid = store.game_uuid
      @name = store.name
      @email = store.email
    end
    queue = Actor[:"queue_#{@game_uuid}"]
    queue.add @uuid
    p queue.ids
    info "q first #{queue.first}"
    
    info store.inspect
  end

  # def run
  # end

  def pitch params = {}
    timers = Actor[:"timers_#{@game_uuid}"]
    timers.async.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game.pitch(params) #TODO params for game on pitch done (move code to game.pitch)

  end

  def pass params = {}
    info 'start player.pass'
    game = Actor[:"game_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    timers.async.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    info "pass to end step"
    game.async.end_step({status: 'passed'})
    info "endstepped"
  end

  def vote params = {}
  end

  def online!
    state = Actor[:"state_#{@game_uuid}"]
    p state.state
    send_ready reply_to: 'connect' if state.state.to_s == 'waiting'
    send_state reply_to: 'connect' if state.state.to_s == 'started'
    send_result reply_to: 'connect' unless %w(waiting started).include?(state.state.to_s)
    info 'online'
  end

  def offline!
    info 'offline'
  end

  def send_result params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'result'}
    ch = state.player_channels[:"player.#{@uuid}"]
    p msg
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_ready params = {}
    state = Actor[:"state_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'ready', start_at: timers.start_at.to_i, pitcher: (players.queue.index(@uuid) == 0 ? 1 : nil)}
    ch = state.player_channels[:"player.#{@uuid}"]
    p msg
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_event ev, params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {
      type: 'event', subtype: ev
    }.merge params
    p @uuid, state.player_channels.keys
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_pitch params = {}
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Time.now.to_i + 60, step: {status: state.step_status} }
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_pass
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'passed'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_vote
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'voted'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_start_step
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    info "::::::ids #{ queue.ids.index(@uuid)}"
    
    msg = {type: 'event', subtype: 'start_step', turn_in: queue.ids.index(@uuid), pitcher_name: queue.pitcher.uglify_name(state.stage), step: {current: state.step, total: state.total_steps, status: state.step_status}}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_end_step params = {}
    state = Actor[:"state_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_step'}
    msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: 0, delta: 0}, timer: Time.now.to_i + 20}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_start_stage
    players = Actor[:"players_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_stage', value: game.stage, turn_in: (players.queue.index(@uuid) || 3)}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_end_stage
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_stage'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def uglify_name(stage)
    %w(s t).include?(stage) ? "Player #{order}" : name
  end

  def state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    statements = Actor[:"statements_#{@game_uuid}"]
    msg = {
      type: 'status',
      state: 'started',
      game: {
        step: {
          current: game.step,
          total: game.total_steps,
          status: game.step_status
        },
        current_stage: game.stage, # one of stages
        conclusion: {},
          replaces: [],
        statements: statements.all,
        player: {
          turn_in: (players.queue.index(@uuid) || 3)
        },

        started_at: timers.start_at.to_i,
        timeout_at: 10
        # timeout_at: timers.next_time
      },
    }
  end

  def send_state params = {}
    info "send_state #{@uuid}"
    state = Actor[:"state_#{@game_uuid}"]
    ch = state.player_channels[:"player.#{@uuid}"]
    info state(params).to_json
    ch[:x].publish state(params).to_json, routing_key: "player.#{@uuid}"
    info state(params).to_json
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
