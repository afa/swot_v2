class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements

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
    @timers = Center.current.async.to_supervise as: :"timers_#{@uuid}", type: Alarms, args: [{uuid: @uuid}.merge(time_params)]
    p 'game', @uuid, 'created'
    state.state = @timers.start_at && @timers.start_at > Time.now.to_i ? :started : :waiting
    cntrl = Control.current.publish_control( (params.has_key?(:players) ? {players: players.players.map{|p| {name: p.name, uuid: p.uuid, email: p.email}}} : {}).merge(type: 'status', uuid: @uuid, replly_to: 'create'))
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
    players.async.build_queue # TODO move to create
    if %w(waiting started).map(&:to_sym).include? state.state
      state.state = :started
      push_event(:started, value: 's')
      players.push_event(:started)
      push_event(:start_stage, value: stage)
      players.push_start_stage
      timers.async.set_out(:stage, setting[:stage_timeout])
      push_event(:start_step)
      players.push_start_step
      # push_state
      # self.players.push_state
      set_out(step == 1 ? :first_pitch : :pitch, settings[step == 1 ? :first_pitch_timeout : :pitch_timeout])
    end
  end

  def start_stage
    info 'TODO start stage'
  end

  def push_event event, params = {}
    {type: 'event', subtype: event}
  end

  def push_state params = {}
    state = int_state
    alarm = Actor[:"timers_#{@uuid}"]
    msg = params.merge status: @status, stage: state.stage, timeout_at: alarm.next_time, started_at: @start_at, players: players.to_hash, step: {total: total_steps, current: step, status: step_status}
    publish msg
  end

  def stage_timeout
    info 'TODO stage timeout'
  end

  def publish hash
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
