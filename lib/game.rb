class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer

  attr_accessor :name, :players
  def self.create params = {}
    uuid = UUID.new.generate
    p uuid
    Center.current.async.to_supervise as: :"game_#{uuid}", type: Game, args: [{uuid: uuid}.merge(params)]
  end

  def initialize params = {}
    @uuid = params[:uuid]
    info "#{@uuid} created"
    # @redis = ::Redis.new(driver: :celluloid)
    Center.current.async.to_supervise as: :"state_#{@uuid}", type: ::State, args: [{game_uuid: @uuid}]
    time_params = {}
    if params[:start]
      time_params.merge!(start: params[:start][:time].to_i) if params[:start][:time]
      @timezone = params[:start][:time_zone]
    end
      
    # time_params = params.inject({}){|r, (k, v)| r.merge(%w(start).map(&:to_sym).include?(k) ? {k => v} : {}) }
    info 'timers'
    @timers = Center.current.async.to_supervise as: :"timers_#{@uuid}", type: Alarms, args: [{uuid: @uuid}.merge(time_params)]
    self.name = params[:name]
    state = Actor[:"state_#{@uuid}"]
    info "state #{state.inspect}"

    self.players = Players.new
    if params[:players]
      params[:players].each do |p|
        p_id = UUID.new.generate
        Center.current.async.to_supervise(as: :"player_#{p_id}", type: Player, args: [p.merge(game_uuid: @uuid, uuid: p_id)])
        # player = Player.new(p.merge(game_uuid: @uuid))
        players.add p_id
        info players.inspect
      end
    end
    p 'game', @uuid, 'created'
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
    players.future.build_queue
    if %w(waiting ready).map(&:to_sym).include? state.state
      @state.state = :running
      push_event(:start_stage, value: 's')
      push_event(:start_step)
      push_state
      self.players.push_event(:started)
      self.players.push_event(:start_stage)
      self.players.push_start_step
      self.players.push_state
      timers.async.set_out(:stage, timers.start_at.to_i + 1500)


    end

  end

  def push_event event, params = {}
    {type: 'event', subtype: event}
  end

  def push_state params = {}
    state = Actor[:"state_#{@uuid}"]
    state.future.step_state
    state.future.step_total
    state.future.step_current
    players.future.to_hash
    state.future.stage
    alarm = Actor[:"timers_#{@uuid}"]
    alarm.future.next_timer
    msg = params.merge status: @status, stage: state.stage, timeout_at: alarm.next_timer, started_at: @start, players: players.to_hash, step: {total: state.step_total, current: state.step_current}
    publish msg
  end

  def publish hash
    info 'todo publish'
  end
  def finalizer
    # Center.current.delete(:"timers_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
