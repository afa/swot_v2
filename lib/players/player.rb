class Player
  include Celluloid
  include Celluloid::IO

  finalizer :finalizer

  attr_accessor :name, :email, :channel

  def initialize params = {}
  end

  def run
  end

  def finalizer
  end

end
