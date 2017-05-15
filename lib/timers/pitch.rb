class Timings::Pitch < Timings::Base
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def self.reg_name
    'pitching'
  end

  def initialize(params = {})
    super
    key = :"#{self.class.reg_name}_timeout"
    @interval = params[key] if params.has_key?(key)
  end

  def set_time(_time)
    raise
  end

  def process
    super
    game = Actor[:"game_#{@guid}"]
    game.async.pitch_timeout(first: false)
  end
end
