require 'hashing'
require 'ostruct'
class State
  include Hashing
  include Celluloid
  attr_accessor :state
  attr_accessor :game_uuid, :game, :players, :statements

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @game = {}
    @players = {}
    @statements = []

  end

  def store_player id
    pl = Actor[:"player_#{id}"]
    if pl && pl.alive?
      @players[id] = pl.as_json
    end

  end

  def add_game id
  end

  def add_statement id
  end

  def locate_player id
    pl = @players[id]
    if pl && pl.alive?
      pl
    end
  end
end
