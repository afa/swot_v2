# require 'sinatra/base'
require 'celluloid/redis'
require 'timers'
require 'channel_actor'
class Game
  include Celluloid
  pubsub = ChannelActor.supervise as: :channel
  puts 'ok'
  @redis = ::Redis.new(driver: :celluloid)
  p @redis
  @redis.publish('tst', 'tt')

  # timers = Timers::Group.new
  configure do
    enable :logging 
  end
  get '/' do
    'ok'
  end
  # every_five_seconds = timers.every(5) { puts "Another 5 seconds" }

  # loop { timers.wait }
end
