# require 'sinatra/base'
class Game
  include Celluloid
  # include Celluloid::Redis
  def initialize
    @uuid = UUID.new.generate
    @redis = ::Redis.new(driver: :celluloid)
    @pubsub = ChannelActor.supervise as: :channel
    @timers = Timers.supervise :as :timers
    # @pubsub = ChannelActor.supervise as: :channel
  end

  def run
    p @uuid
    puts 'ok'
    @timers.async.run
    @pubsub.async.run
    @redis.publish('tst', 'tt')
    sleep 10
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
