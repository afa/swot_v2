class Timers::Ranging < Timers::Base
  include Cellulod
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def self.reg_name
    'ranging'
  end

  def initialize params = {}
    super
    # for others there is key
    key = :"#{self.class.reg_name}_timeout"
    if params.has_key?(key)
      @interval = params[key]
    end
  end

  def set_time time
    raise
  end

  def process
    super
    game = Actor[:"game_#{@guid}"]
    game.async.ranging_timeout
  end
end
