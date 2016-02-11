class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements, :setting

  attr_accessor :name, :setting
  def self.create params = {}
    uuid = UUID.new.generate
    p uuid
    Center.current.async.to_supervise as: :"game_#{uuid}", type: Game, args: [{uuid: uuid}.merge(params)]
  end

  def int_state
    Actor[:"state_#{@uuid}"]
  end

  def initialize params = {}
    @uuid = params[:uuid]
    sett = Store::Setting.find(game_uuid: @uuid)
    unless sett
      sett = Store::Setting.new(game_uuid: @uuid)
      sett.save
    end
    @setting = sett
    info "#{@uuid} created"
    # @redis = ::Redis.new(driver: :celluloid)
    Center.current.to_supervise as: :"state_#{@uuid}", type: State, args: [{game_uuid: @uuid}]
    time_params = {}
    if params[:start]
      time_params.merge!(start: params[:start][:time].to_i) if params[:start][:time]
      @timezone = params[:start][:time_zone]
    end
      
    # time_params = params.inject({}){|r, (k, v)| r.merge(%w(start).map(&:to_sym).include?(k) ? {k => v} : {}) }
    self.name = params[:name]
    state = Actor[:"state_#{@uuid}"]
    info "state #{state.inspect}"

    Center.current.to_supervise(as: :"players_#{@uuid}", type: Players, args: [{game_uuid: @uuid}])
    players = Actor[:"players_#{@uuid}"]
    if params[:players]
      params[:players].each do |p|
        p_id = UUID.new.generate
        Center.current.to_supervise(as: :"player_#{p_id}", type: Player, args: [p.merge(game_uuid: @uuid, uuid: p_id)])
        players.async.add p_id
      end
    end
    info 'timers'
    timers = Center.current.async.to_supervise as: :"timers_#{@uuid}", type: Alarms, args: [{uuid: @uuid}.merge(time_params)]
    p 'game', @uuid, 'created'
    state.state = timers.start_at && timers.start_at > Time.now.to_i ? :started : :waiting
    cntrl = Control.current.publish_control( (params.has_key?(:players) ? {players: players.players.map{|p| {name: p.name, uuid: p.uuid, email: p.email}}} : {}).merge(type: 'status', uuid: @uuid, replly_to: 'create'))
    Control.current.add_game(@uuid)
    state.add_game @uuid
    async.run
  end

  def onconnect
    push_state reply: 'connect'
  end

  def run
    p @uuid
    puts 'ok'

    # @timers.async.run
    # @pubsub.async.run
    # @redis.publish('tst', 'tt')
  end

  def start
    # receive start
    # before start prepare queue
    # on start timer for pitch, set state, send to players
    # check players online
    #
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    timers = Actor[:"timers_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    players.async.build_queue # TODO move to create
    if %w(waiting started).map(&:to_sym).include? state.state
      state.state = :started
      # push_event(:started, value: 's')
      # players.push_event(:started)
      async.publish(type: 'event', subtype: 'start_stage', value: stage)
      # async.push_event(:start_stage, value: stage)
      players.async.push_start_stage
      timers.async.set_out(:stage, setting[:stage_timeout])
      async.publish(type: 'event', subtype: 'start_step')
      # async.push_event(:start_step)
      players.async.push_start_step
      timers.async.set_out(step == 1 ? :first_pitch : :pitch, setting[step == 1 ? :first_pitch_timeout : :pitch_timeout])
      # async.push_state
      # players.async.push_state
    end
  end

  def start_stage #whats?
    info 'TODO start stage'
  end

  def stage_timeout
  end

  def pitch_timeoutA params = {}
  end

  def push_event event, params = {}
    {type: 'event', subtype: event}
  end

  def push_state params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    alarm = Actor[:"timers_#{@uuid}"]
    msg = params.merge status: state.state, stage: state.stage, timeout_at: alarm.next_time, started_at: alarm.start_at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    publish msg
  end

  def stage_timeout
    info 'TODO stage timeout'
  end

  def publish hash
    state = int_state
    info "publish game #{hash.inspect}"
    fan = state.game[:fan]
    fan.publish hash.to_json, routing_key: "game.#{@uuid}"
  end

  def finalizer
    # Center.current.delete(:"timers_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
