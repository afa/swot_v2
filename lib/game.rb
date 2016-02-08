class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements

  attr_accessor :name, :players
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
    self.players = Actor[:"players_#{@uuid}"]
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
    timers = Actor[:"timers_#{@uuid}"]
    players.async.build_queue
    if %w(waiting started).map(&:to_sym).include? state.state
      state.state = :started
      push_event(:started, value: 's')
      self.players.push_event(:started)
      push_event(:start_stage, value: stage)
      self.players.push_start_stage
      push_event(:start_step)
      self.players.push_start_step
      push_state
      self.players.push_state
      timers.async.set_out(:stage, Time.now.to_i + 1500)
      timers.async.set_out(:pitch, Time.now.to_i + 20)
    end
  end

  def start_stage

  end
  def push_event event, params = {}
    {type: 'event', subtype: event}
  end

  def push_state params = {}
    state = int_state
    alarm = Actor[:"timers_#{@uuid}"]
    msg = params.merge status: @status, stage: state.stage, timeout_at: alarm.next_time, started_at: @start, players: players.to_hash, step: {total: total_steps, current: step}
    publish msg
  end

  def publish hash
    info "todo publish game #{hash.inspect}"
  end
  def finalizer
    # Center.current.delete(:"timers_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
