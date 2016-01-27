require 'players/player'
require 'players/queue'
# require 'forwardable'
class Players
  # extend Forwardable
  include Celluloid

  attr_accessor :players
  # def_delegators :@players, :<<, :+

  def initialize params = {}
    if params[:game_uuid]
      state = Actor[:"state_#{params[:game_uuid]}"]
      state.players.each{|i| add(i) }
    else
      @players = []
    end
  end

  def push_event event, params = {}
    players.each{|p| p.push_event event, params }
  end

  def push_state params = {}
    players.each{|p| p.push_state params }
  end

  def players
    @players.map{|i| Actor["player_#{i}"] }
  end

  def add player
    state = Actor[:"state_#{params[:game_uuid]}"]
    # state.async
  end


end
