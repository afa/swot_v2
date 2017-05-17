class Statements
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :statements, :current, :game_uuid
  attr :voting, :last_stat
  def initialize(params = {})
    @game_uuid = params[:game_uuid]
    @statements = []
    @current = []
    @voting = nil
    @visible = []
    subscribe :save_game_data, :save_game_data
  end

  def not_mine(guid)
    guid != @game_uuid
  end

  def save_game_data(_topic, game_id)
    return if not_mine(game_id)
    # sync_statements
    publish :game_data_saved, @game_uuid, :statements
  end

  def sync_statements
    # info 'syncing statements'
    sts = @statements.select { |st| !Store::Statement.find(uuid: st.uuid).first }
    sts.each { |st| Store::Statement.create(st.to_store) }
    info "synced #{sts.size} statements" unless sts.empty?
  end

  def find(uuid)
    @statements.detect { |st| st.uuid == uuid }
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
    visibles = arr.map { |item| find item }
    visibles.each_with_index { |item, idx| item.position = idx + 1 }
    visibles
  end

  def visible
    visible_for_buf
  end

  def validate_statement(params = {})
    repl_count = params.key?(:to_replace) && params[:to_replace] ? params[:to_replace].size : 0
    return { type: 'error', value: 'to_many' } if @visible.size - repl_count > 6
    if @current.detect { |s| params[:value] == find(s).value }
      return { type: 'error', value: 'duplicate' }
    end
    if params[:value].force_encoding('UTF-8').size > 75
      return { type: 'error', value: 'too_long' }
    end
    return { type: 'error', value: 'empty' } if params[:value].strip.size == 0
    {}
  end

  def check_triple_decline
    state = Actor[:"state_#{@game_uuid}"]
    stats = in_stage(state.stage)
    dec_count = [state.setting[:declined_in_row_statements].to_i, stats.size].min
    return false if dec_count < state.setting[:declined_in_row_statements].to_i
    stats[-dec_count, dec_count].all? { |s| s.status == 'declined' }
  end

  def in_stage(stage)
    @statements.select { |st| st.stage == stage }
  end

  def rebuild_visible_for(stage)
    vis = []
    @statements.select { |st| st.stage == stage && st.status == 'accepted' }.sort_by(&:step).each do |st|
      st.replaces.each { |r| vis.delete r }
      vis << st.uuid
    end
    vis
  end

  def range_auto
    statements = Actor[:"statements_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    stmnts = %w(s w o t).map(&:to_sym).inject([]) do |res, st|
      res + statements.visible_for_buf(statements.rebuild_visible_for(st))
    end
    stmnts.each do |st|
      players.was_online.each do |pl|
        st.add_impo(pl.uuid, 3, true) # true for auto
      end
    end
  end

  def range_for(params = {})
    stage_swot = State::STAGES.fetch(params[:stage], swot: :end)[:swot]
    statements = Actor[:"statements_#{@game_uuid}"]
    stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot))
    st = stmnts[params[:index].to_i - 1]
    st.add_impo(params[:player], params[:value]) # true for auto
  end

  def add(params = {})
    er = validate_statement params
    return er unless er.empty?
    uuid = UUID.new.generate
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    replace = []
    params[:to_replace].each { |idx| replace << @visible[idx - 1] } if params[:to_replace]

    val = params[:value].strip
    statement = Statement.new(value: val,
                              author: queue.pitcher.uuid,
                              replaces: replace.compact,
                              uuid: uuid,
                              game_uuid: @game_uuid,
                              stage: state.stage,
                              step: state.step)
    @statements << statement
    @current << uuid
    replace.map { |st| find st }.compact.each { |st| st.replaced_by! uuid }
    active.each_with_index { |st, idx| st.position = idx + 1 }
    @voting = uuid
    {}
  end

  def init_importances
    players = Actor[:"players_#{@game_uuid}"]
    pl_ids = players.players.select(&:was_online).map(&:uuid)
    stmnts = %w(s w o t).map(&:to_sym).inject([]) { |res, st| res + visible_for_buf(rebuild_visible_for(st)) }
    stmnts.each do |st|
      pl_ids.each { |pl_id| st.add_impo(pl_id, 3, true) }
    end
  end

  def copy_before
    @statements.each(&:copy_before)
  end

  def update_importance_score
    @statements.select { |st| st.status == 'accepted' }.each(&:update_importance_score)
  end

  def rescore
    accepted = @statements.select { |stat| stat.status == 'accepted' }
    s_sum = accepted.inject(0.0) { |rez, stt| rez + stt.importance_score_raw.to_f }
    s_sum = 1.0 if s_sum.to_f == 0.0
    accepted.each do |st|
      st.importance_score = st.importance_score_raw * 100.0 / s_sum
    end
  end

  def count_pitchers_score
    players = Actor[:"players_#{@game_uuid}"]
    players.players.each do |player|
      # player.score.pitcher_before_ranging = player.score.pitcher if opts[:save_before]
      player.pitcher_score = pitcher_score_for(player)
    end
  end

  def pitcher_score_for(player)
    all_contributions = @statements.select { |stat| stat.status == 'accepted' }.map(&:contribution)
    all_contributions.inject(0.0) { |rez, xtr| rez + xtr[player.uuid.to_s].to_f }
  end

  def update_visible
    return unless @voting
    w_stat = find(@voting)
    unless w_stat
      @voting = nil
      @last_stat = nil
      return
    end
    if w_stat.status == 'accepted'
      w_stat.replaces.each { |st| @visible.delete st }
      @visible << w_stat.uuid
    end
    @last_stat = @voting
    @voting = nil
  end

  def mapped_current
    @current.map { |st| find st }
  end

  def find_for_stage(st)
    mapped_current.detect { |cur| cur.stage == st }
  end

  def active_js(player = nil)
    active.map { |st| st.as_json(player) }
  end

  def active
    visible
  end

  def all
    mapped_current.map(&:as_json)
  end

  def by(sym, val)
    @statements.select { |st| st.send(sym) == val }
  end

  def clean_current
    @current = []
    @visible = []
    @last_stat = nil
    @voting = nil
  end
end
