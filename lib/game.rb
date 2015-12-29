class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer

  attr_accessor :name, :players
  def self.create params = {}
    uuid = UUID.new.generate
    p uuid
    Center.current.to_supervise as: :"game_#{uuid}", type: Game, args: [{uuid: uuid}.merge(params)]
  end

  def initialize params = {}
    @uuid = params[:uuid]
    info "#{@uuid} created"
    @redis = ::Redis.new(driver: :celluloid)
    @timers = Center.current.to_supervise as: :"timers_#{@uuid}", type: Alarms, args: [{uuid: @uuid}]
    self.name = params[:name]
    self.players = Array.new
    if params[:players]
      params[:players].each do |p|
        player = Player.new(p.merge(game_uuid: @uuid))
        players << player
      end
    end
  end

  def run
    p @uuid
    puts 'ok'

    # @timers.async.run
    # @pubsub.async.run
    # @redis.publish('tst', 'tt')
  end

  def finalizer
    # Center.current.delete(:"timers_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
