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

    self.players = Array.new
    if params[:players]
      params[:players].each do |p|
        p_id = UUID.new.generate
        Center.current.async.to_supervise(as: :"player_#{p_id}", type: Player, args: [p.merge(game_uuid: @uuid, uuid: p_id)])
        # player = Player.new(p.merge(game_uuid: @uuid))
        players << p_id
        info players.inspect
      end
    end
    Center.current.async.to_supervise as: "state_#{@uuid}", type: ::State, args: {}
    p 'game', @uuid, 'created'
    async.run
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
    if %w(waiting ready).map(&:to_sym).include? @state.state
      @state.state = :running
      push_event(:running)
      push_state
      self.players.push_event(:started)
      self.players.push_state
    end
  end

  def push_event event, params = {}
  end

  def push_state params = {}
  end

  def finalizer
    # Center.current.delete(:"timers_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
