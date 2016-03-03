require 'hashing'
require 'ostruct'
class State
  include Hashing
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  attr_accessor :state, :step, :total_steps, :step_status, :stage
  attr_accessor :game_uuid, :game, :players, :player_channels, :setting, :prev_pitcher
  STAGES = {
    s: {beetwen: false, order: 1, name: 'Strengths', swot: :s},
    sw: {beetwen: true, order: 2, swot: :s},
    w: {beetwen: false, order: 3, name: 'Weaknesses', swot: :w},
    wo: {beetwen: true, order: 4, swot: :w},
    o: {beetwen: false, order: 5, name: 'Opportunities', swot: :o},
    ot: {beetwen: true, order: 6, swot: :o},
    t: {beetwen: false, order: 7, name: 'Threats', swot: :t},
    tr: {beetwen: true, order: 8, swot: :t},
    rs: {beetwen: false, order: 9, swot: :s},
    rw: {beetwen: false, order: 10, swot: :w},
    ro: {beetwen: false, order: 11, swot: :o},
    rt: {beetwen: false, order: 12, swot: :t},
    end: {beetwen: false, order: 13, swot: nil}
  }

  STEP_STATUSES = {
    pitch: {active: true, name: 'pitch', order: 1},
    vote: {active: true, name: 'vote', order: 2},
    end: {active: false, name: 'end', order: 3}
  }

  def to_swot(stg)
    STAGES[stg][:swot]
  end

  def first_enum(hash)
    frst = hash.values.map{|i| i[:order] }.min
    hash.select{|k, v| v[:order] == frst }.keys.first
  end

  def next_enum(hash, e)
    return nil unless e
    ord = hash[e][:order]
    idx = hash.values.map{|v| v[:order] }.select{|o| o > ord }.min
    return nil unless idx
    hash.select{|k, v| v[:order] == idx }.keys.first
  end

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    info "state init for #{@game_uuid}"
    @game = {}
    @players = {}
    @stage = nil
    @player_channels = {}
    unless try_recover
      load_default_settings
      init
    end


  end

  def try_recover
    store_game = Store::Game.find(uuid: @game_uuid)
    return false unless store_game
    false # change when recovery will work TODO
  end

  def init
    unless Actor[:"statements_#{@game_uuid}"]
      Center.current.to_supervise as: :"statements_#{@game_uuid}", type: Statements, args: [{game_uuid: @game_uuid}]
    end
    statements = Actor[:"statements_#{@game_uuid}"]
    @step = 1
    @total_steps = @setting[:max_steps] || 12
    @step_status = first_enum(STEP_STATUSES)
    statements.clean_current

    info 'init state done'
  end

  def load_default_settings
    @setting = Store::Setting.for_game(@game_uuid)
  end

  def stage
    @stage ||= @state == :started ? first_enum(STAGES) : nil
  end

  def next_stage!
    if @state == :started
      @stage = next_enum(STAGES, @stage)
    end
    statements.clear_current
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

  # def locate_player id
  #   pls = Actor[:"players_#{@game_uuid}"]
  #   pl = @players[id]
  #   if pl && pl.alive?
  #     pl
  #   end
  # end
end
