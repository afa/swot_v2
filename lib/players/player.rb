class Player
  include Celluloid
  include Celluloid::IO

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid

  def initialize params = {}
          Store::Player.create(params.merge(game_uuid: @uuid))
  end

  def run
  end

  def finalizer
  end

end
