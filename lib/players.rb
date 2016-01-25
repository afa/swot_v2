require 'players/player'
require 'players/queue'
require 'forwardable'
class Players
  extend Forwardable

  attr_accessor :players
  def_delegators :@players, :<<, :+

  def initialize params = {}
    if params[:game_uuid]
      @state = Celluloid::Actor[:"state_#{params[:game_uuid]}"]
      @state.feature.players
      self.players = @state.players
    else
      self.players = []
    end
  end

  def players

end
