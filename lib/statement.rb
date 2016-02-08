class Statement
  include Celluloid::Internals::Logger

  attr_accessor :value, :author, :replaces, :uuid, :position, :game_uuid, :stage, :step

  def initialize params = {}
  end

end
