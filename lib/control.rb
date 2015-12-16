class Control
  include Celluloid
  CONTROL_CHANNEL = 'swot/control'

  attr_accessor :control_channel
  def initialize
    @redis = ::Redis.new(driver: :celluloid)
    
  end

  def run
    self.control_channel = @redis.subscribe(CONTROL_CHANNEL) do |on|
      on.message do |ch, msg|
        p msg
      end
      on.subscribe do
        p 'sub'
      end
      on.unsubscribe do
        p 'un'
      end
    end
    p 'ex ctl'
  end
end
