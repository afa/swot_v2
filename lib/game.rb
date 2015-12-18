# require 'sinatra/base'
class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer
  # include Celluloid::Redis
  def initialize
    @uuid = UUID.new.generate
    info "#{@uuid} created"
    @redis = ::Redis.new(driver: :celluloid)
    @pubsub = Center.current.to_supervise as: :"game_#{@uuid}", type: ChannelActor, args: [{}]
    @timers = Center.current.to_supervise as: :"timers_#{@uuid}", type: Alarms, args: [{}]
    # @pubsub = ChannelActor.supervise as: :channel
    # @timers = Alarms.supervise as: :timers
    # @pubsub = ChannelActor.supervise as: :channel
    async.run
  end

  def run
    p @uuid
    puts 'ok'
    # @timers.async.run
    # @pubsub.async.run
    # @redis.publish('tst', 'tt')
  end

  def finalizer
    @timers.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
  # timers = Timers::Group.new
  # configure do
  #   enable :logging 
  # end
  # get '/' do
  #   'ok'
  # end
  # every_five_seconds = timers.every(5) { puts "Another 5 seconds" }

  # loop { timers.wait }
end
