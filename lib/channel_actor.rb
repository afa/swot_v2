require 'celluloid'
class ChannelActor
  include Celluloid
  @redis = ::Redis.new(driver: :celluloid)
  @redis.subscribe('tst') do |on|
    on.message do |ch, msg|
      p ch, msg
    end
    on.subscribe do |ch, msg|
      p ch, msg
    end
  end
end
