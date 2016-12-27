class Statements
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :statements, :current, :game_uuid
  attr :voting, :last_stat
  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @statements = []
    @current = []
    @voting = nil
    @visible = []
    subscribe :save_game_data, :save_game_data
  end

  def save_game_data topic, game_id
    return unless game_id == @game_uuid
    # sync_statements
    publish :game_data_saved, @game_uuid, :statements
  end

  def sync_statements
    info 'syncing statements'
    store = Store::Statement.find(game_uuid: @game_uuid).to_a
    sts = @statements.select{|s| !Store::Statement.find(uuid: s.uuid).first }
    sts.each{|s| Store::Statement.create(s.to_store) }
    info "synced #{sts.size} statements" if sts.size > 0
  end

  def find(uuid)
    @statements.detect{|s| s.uuid == uuid }
  end

  def voting
    return nil unless @voting
    find(@voting)
  end

  def last_stat
    return nil unless @last_stat
    find(@last_stat)
  end

  def visible_for_buf(arr = @visible)
    v = arr.map{|s| find s }
    v.each_with_index{|s, i| s.position = i + 1 }
    v
  end

  def visible
    visible_for_buf
  end

  def validate_statement params = {}
    repl_count = params.has_key?(:to_replace) && params[:to_replace] ? params[:to_replace].size : 0
    if @visible.size - repl_count > 6
      return { type: 'error', value: 'to_many' }
    end
    if @current.detect{|s| params[:value] == find(s).value }
      return { type: 'error', value: 'duplicate' }
    end
    if params[:value].force_encoding('UTF-8').size > 75
      return { type: 'error', value: 'too_long' }
    end
    if params[:value].strip.size == 0
      return { type: 'error', value: 'empty' }
    end
    {}
  end

  def check_triple_decline
    state = Actor[:"state_#{@game_uuid}"]
    stats = in_stage(state.stage)
    dec_count = [state.setting[:declined_in_row_statements].to_i, stats.size].min
    return false if dec_count < state.setting[:declined_in_row_statements].to_i
    # dec_count = state.setting[:declined_in_row_statements].to_i
    stats[-dec_count, dec_count].all?{|s| s.status == 'declined' }
  end

  def in_stage(stage)
    @statements.select{|s| s.stage == stage }
  end

  def rebuild_visible_for(stage)
    vis = []
    @statements.select{|s| s.stage == stage && s.status == 'accepted' }.sort_by{|s| s.step }.each do |s|
      s.replaces.each{|r| vis.delete r }
      vis << s.uuid
    end
    vis
  end

  def range_auto
    statements = Actor[:"statements_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    stmnts = %w(s w o t).map(&:to_sym).inject([]){|res, s| res + statements.visible_for_buf(statements.rebuild_visible_for(s)) }
    # st = stmnts[params[:index].to_i - 1]
    stmnts.each do |st|
      players.was_online.each do |pl|
        st.add_impo(pl.uuid, 3, true)  #, true for auto
      end
    end
  end

  def range_for params = {}
    state = Actor[:"state_#{@game_uuid}"]
    stage_swot = State::STAGES.fetch(params[:stage], {swot: :end})[:swot]
    # stage_swot = State::STAGES.fetch(state.stage, {swot: :end})[:swot]
    statements = Actor[:"statements_#{@game_uuid}"]
    stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot))
    st = stmnts[params[:index].to_i - 1]
    st.add_impo(params[:player], params[:value])  #, true for auto

    #{ player: params[:player], value: params[:value], index: params[:index], stage: State::STAGES[state.stage][:swot] }
    #value, index, stage, player
  end

  def add params = {}
    er = validate_statement params
    return er unless er.empty?
    uuid = UUID.new.generate
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    replace = []
    if params[:to_replace]
      info "to replace #{params[:to_replace].inspect}"
      params[:to_replace].each{|idx| replace << @visible[idx - 1] }
    end

    val = params[:value].strip
    statement = Statement.new value: val, author: queue.pitcher.uuid, replaces: replace.compact, uuid: uuid, game_uuid: @game_uuid, stage: state.stage, step: state.step
    @statements << statement
    @current << uuid
    replace.map{|s| find s }.compact.each{|s| s.replaced_by! uuid }
    active.each_with_index{|s, i| s.position = i + 1 }
    # statement.set_contribution ??? nahua?
    @voting = uuid
    {}
  end

  def init_importances
    players = Actor[:"players_#{@game_uuid}"]
    pl_ids = players.players.select(&:was_online).map(&:uuid)
    stmnts = %w(s w o t).map(&:to_sym).inject([]){|res, s| res + visible_for_buf(rebuild_visible_for(s)) }
    stmnts.each do |st|
      pl_ids.each{|p| st.add_impo(p, 3, true) }
    end
  end

  def copy_before
    @statements.each{|s| s.copy_before }
  end

  def update_importance_score
    @statements.select{|s| s.status == 'accepted' }.each{|s| s.update_importance_score }
  end

  def rescore
    s_sum = @statements.select{|s| s.status == 'accepted' }.inject(0.0){|r, s| r + s.importance_score_raw.to_f }
    s_sum = 1.0 if s_sum.to_f == 0.0
    @statements.select{|s| s.status == 'accepted' }.each do |s|
      s.importance_score = s.importance_score_raw * 100.0 / s_sum
    end
  end

  def count_pitchers_score
    all_contributions = @statements.select{|s| s.status == 'accepted' }.map &:contribution

    players = Actor[:"players_#{@game_uuid}"]
    players.players.each do |player|
      # player.score.pitcher_before_ranging = player.score.pitcher if opts[:save_before]
      player.pitcher_score = all_contributions.inject(0.0){|r, x| r + x[player.uuid.to_s].to_f }
    end
  end

  def update_visible
    return unless @voting
    s = find(@voting)
    unless s
      @voting = nil
      @last_stat = nil
      return
    end
    if s.status == 'accepted'
      s.replaces.each{|s| @visible.delete s }
      @visible << s.uuid
    end
    @last_stat = @voting
    @voting = nil
  end

  def mapped_current
    @current.map{|s| find s }
  end

  def find_for_stage st
    mapped_current.detect{|s| s.stage == st }
  end

  def active_js(player = nil)
    active.map{|s| s.as_json(player) }
  end

  def active
    visible
  end

  def all
    mapped_current.map(&:as_json)
  end

  def by(sym, val)
    @statements.select{|s| s.send(sym) == val }
  end

  def clean_current
    @current = []
    @visible = []
    @last_stat = nil
    @voting = nil
  end

end
