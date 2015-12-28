require 'players/player'
require 'players/queue'
require 'forwardable'
class Players
  extend Forwardable

  attr_accessor :players
  def_delegators :@players, :<<, :+

  def initialize params = {}
    @players = []
  end

end
