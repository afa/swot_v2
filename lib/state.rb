require 'hashing'
require 'ostruct'
class State
  include Hashing
  include Celluloid
  include Celluloid::Internals::Logger
  attr_accessor :state, :step, :total_steps, :step_status, :stage
  attr_accessor :game_uuid, :game, :players, :statements, :player_channels

  def initialize params = {}

    info "state init"
    @game_uuid = params[:game_uuid]
    info @game_uuid
    @game = {}
    @players = {}
    @statements = []
    @stage = 'w'
    @player_channels = {}
    @step = params[:step] || 1
    @total_steps = params[:total_steps] || 60
    @step_status = params[:step_status] || :pitch


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
