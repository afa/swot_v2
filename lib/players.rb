require 'players/player'
require 'players/queue'
require 'forwardable'
class Players
  extend Forwardable

  attr_accessor :players
  def_delegators :@players, :<<, :+

  def initialize params = {}
    if params[:game_uuid]
      state = Celluloid::Actor[:"state_#{params[:game_uuid]}"]
      state.feature.players
      state.players.each{|i| add(i) }
    else
      @players = []
    end
  end

  def players
    @players.map{|i| Actor["player_#{i}"] }
  end

  def add player
    state = Celluloid::Actor[:"state_#{params[:game_uuid]}"]
    # state.async
  end


end
