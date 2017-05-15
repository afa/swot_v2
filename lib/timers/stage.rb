class Timings::Stage < Timings::Base
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def self.reg_name
    'stage'
  end

  def initialize(params = {})
    super
    # for others there is key
    key = :"#{self.class.reg_name}_timeout"
    @interval = params[key] if params.has_key?(key)
  end

  def set_time(time)
    raise
  end

  def process
    super
    game = Actor[:"game_#{@guid}"]
    game.async.stage_timeout
  end
end
