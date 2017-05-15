class Timings::Start < Timings::Base
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def self.reg_name
    'start'
  end

  def initialize(params = {})
    super
    # for others there is key
    if params.has_key?(:start)
      @at = params[:start]
      @timer = after(@at - Time.now.to_i) { process }
    end
  end

  def start
    raise
  end

  def process
    super
    game = Actor[:"game_#{@guid}"]
    game.async.start
  end
end
