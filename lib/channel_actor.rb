class ChannelActor
  include Celluloid
  # include Celluloid::Redis
  def initialize
    @redis = ::Redis.new(driver: :celluloid)
  end

  def run
    p 'st'
    @redis.subscribe('tst') do |on|
      on.message do |ch, msg|
        p ch, msg
      end
      # on.subscribe do |ch, msg|
      #   p ch, msg
      # end
    end
  end
end
