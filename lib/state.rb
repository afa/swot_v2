require 'hashing'
require 'ostruct'
class State
  include Hashing
  include Celluloid
  include Celluloid::Internals::Logger
  attr_accessor :state, :step, :total_steps, :step_status, :stage
  attr_accessor :game_uuid, :game, :players, :statements, :player_channels, :settings
  STAGES = {
    s: {beetwen: false, order: 1, name: 'Strengths'},
    sw: {beetwen: true, order: 2},
    w: {beetwen: false, order: 3, name: 'Weaknesses'},
    wo: {beetwen: true, order: 4},
    o: {beetwen: false, order: 5, name: 'Opportunities'},
    ot: {beetwen: true, order: 6},
    t: {beetwen: false, order: 7, name: 'Threats'},
    tr: {beetwen: true, order: 8},
    rs: {beetwen: false, order: 9},
    ro: {beetwen: false, order: 10},
    rw: {beetwen: false, order: 11},
    rt: {beetwen: false, order: 12}
  }

  STEP_STATUSES = {
    pitch: {active: true, name: 'pitch', order: 1},
    catch: {active: true, name: 'catch', order: 2},
    end: {active: false, name: 'end', order: 3}
  }

  def first_enum(hash)
    frst = hash.values.map{|i| i[:order] }.min
    hash.select{|k, v| v[:order] == frst }.keys.first
  end

  def next_enum(hash, e)
    ord = hash[e][:order]
    idx = hash.values.map{|v| i[:order] }.select{|o| o > ord }.min
    hash.select{|k, v| v[:order] == idx }.keys.first
  end

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    info "state init for #{@game_uuid}"
    @game = {}
    @players = {}
    @statements = []
    @stage = nil
    @player_channels = {}
    unless try_recover
      __load_default_settings__
      __init__
    end


  end

  def try_recover
    store_game = Store::Game.find(uuid: @game_uuid)
    return false unless store_game
  end

  def  __init__
    @step = 1
    @total_steps = @settings[:total_steps] || 60
    @step_status = first_enum(STEP_STATUSES)
    info 'init state done'
  end

  def __load_default_settings__
    @settings = {total_steps: 60}
  end

  def stage
    @stage ||= @state == :started ? first_enum(STAGES) : nil
  end

  def next_stage!
    if @state == :started
      @stage = next_enum(STAGES, @stage)
    end
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
