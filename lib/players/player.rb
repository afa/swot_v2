class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis, :order, :score, :online

  def initialize params = {}
    @online = false
    # @redis ||= ::Redis.new(driver: :celluloid)
    @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      unless store
        info "player #{params.inspect} started"
        store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state], uuid: params[:uuid], game_uuid: params[:game_uuid], score: params[:score] || 0.0)
      end
      @uuid = store.uuid
      @game_uuid = store.game_uuid
      @name = store.name
      @email = store.email
      @score = store.score
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
    # timers = Actor[:"alarms_#{@game_uuid}"]
    # timers.async.set_out :pitch, nil
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game.pitch(params) #TODO params for game on pitch done (move code to game.pitch)

  end

  def pass params = {}
    info 'start player.pass'
    game = Actor[:"game_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    # timers.async.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    info "pass to end step"
    game.async.end_step({status: 'passed'})
    info "endstepped"
  end

  def vote params = {}
    
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    send_vote(value: params[:value])
    game.vote(result: params[:value], player: @uuid) #TODO params for game on pitch done (move code to game.pitch)
  end

  def online!
    @online = true
    info "#{@uuid} online"
    state = Actor[:"state_#{@game_uuid}"]
    async.send_ready reply_to: 'connect' if state.state.to_s == 'waiting'
    async.send_state reply_to: 'connect' if state.state.to_s == 'started'
    async.send_result reply_to: 'connect' unless %w(waiting started).include?(state.state.to_s)
    info 'online'
  end

  def offline!
    @online = false
    info "#{@uuid} offline"
  end

  def publish msg
    if @online
      ch = Actor[:"chnl_#{@uuid}"]
      if ch
        p 'chnl ok'
      else

      end
      ch.publish msg.to_json
    else
      info "player #{@uuid} offline"
    end
    info msg.inspect
  end

  def send_result params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'result'}
    publish msg
  end

  def send_ready params = {}
    state = Actor[:"state_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'ready', start_at: Timings::Start.instance(@game_uuid).at, pitcher: (players.queue.index(@uuid) == 0 ? 1 : nil)}
    publish msg
  end

  def send_event ev, params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {
      type: 'event', subtype: ev
    }.merge params
    p @uuid, state.player_channels.keys
    publish msg
  end

  def send_pitch params = {}
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Time.now.to_i + 60, step: {status: state.step_status} }
    publish msg
  end

  def send_pass
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'passed'}
    publish msg
  end

  def send_vote params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'voted'}.merge(params)
    publish msg
  end

  def send_start_step
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    info "::::::ids #{ queue.ids.index(@uuid)}"
    msg = {type: 'event', subtype: 'start_step', turn_in: queue.ids.index(@uuid), pitcher_name: queue.pitcher.uglify_name(state.stage), step: {current: state.step, total: state.total_steps, status: state.step_status}}
    publish msg
  end

  def send_end_step params = {}
    state = Actor[:"state_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: 0, delta: 0}, timer: Time.now.to_i + 20}
    publish msg
  end

  def send_start_stage
    players = Actor[:"players_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_stage', value: game.stage, turn_in: (players.queue.index(@uuid) || 3)}
    publish msg
  end

  def send_end_stage
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Timings.instance(@uuid).next_interval}
    publish msg
  end

  def uglify_name(stage)
    %w(s t).include?(stage) ? "Player #{order}" : name
  end

  def state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    statements = Actor[:"statements_#{@game_uuid}"]
    info "current statements #{statements.all.map(&:as_json)}"
    msg = {
      type: 'status',
      state: state.state,
      game: {
        step: {
          current: game.step,
          total: game.total_steps,
          status: game.step_status
        },
        current_stage: game.stage, # one of stages
        conclusion: {},
        replaces: [],
        statements: statements.all.map(&:as_json),
        player: {
          turn_in: (players.queue.index(@uuid) || 3)
        },

        started_at: Timings::Start.instance(@game_uuid).at,
        timeout_at: Timings.instance(@game_uuid).next_interval
      },
    }
  end

  def send_state params = {}
    info "send_state #{@uuid}"
    publish state(params)
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
