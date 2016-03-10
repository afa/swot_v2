class OnlineLogger < Ohm::Model

  TYPES_WITH_ARGS = %i(next_stage statement_pitched vote_added vote_timeouts
                          statement_results importance_added player_connected player_disconnected)
  attribute :game_id
  index :game_id
  collection :rows, :OnlineLogRow, :logger
  counter :next_row

  delegate :log_trigger, to: :msg

  def data
    rows.sort_by(:created_at, order: 'asc').map{|x| x.data.merge created_at: x.created_at.utc.strftime("%T:%L") }
    # ---after destructive sync redo--- (game_logger_rows.all + online_logger.rows).map {|x| x.attributes['data'].merge created_at: x.created_at.utc.strftime("%T:%L") }
    # self.reload.game_logger_rows.all.map {|x| x.attributes['data'].merge created_at: x.created_at.utc.strftime("%T:%L") }
  end

  def write game, type, *args
    data = TYPES_WITH_ARGS.include?(type.to_sym) ? self.send(type, game, args.first) : self.send(type, game)
    incr :next_row
    row = OnlineLogRow.create data: data, logger_id: self.id, created_at: Time.now, online_id: self.next_row
    log_trigger :new_message, data.merge(created_at: row.created_at.strftime("%T:%L"))
  end

  def make_rows(arr = [])
    lst = arr.map(&:online_id).map(&:to_i).max.to_i
    if lst > 0 && lst > self.next_row
      incr :next_row, lst - nxt_row + 1
    end

    arr.each do |item|
      incr :next_row if item.online_id.to_i == 0
      OnlineLogRow.create data: item.data, logger_id: self.id, created_at: item.created_at, online_id: (item.online_id.to_i > 0 ? item.online_id : next_row)
    end
  end

  def new_rows ids
    (rows.to_a.map{|i| i.online_id || i.id } - ids).map{|i| rows.find(online_id: i).first || rows.find(id: i).first }
  end

  def msg
    @msg ||= Messaging.instance
  end

  private

  def start(game)
    { 
      type: :start,
      pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      queue: begin [ game.players_queue.current_pitcher.name ]; rescue PlayersQueue::ErrorEmptyQueue; [] end + game.players_queue.next_pitchers.map(&:name),
      time_left: time_left(game)
    }
  end

  def next_stage game, next_st
    stats = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_stage.raw_counters)
    end
    { type: :next_stage, from: game.previous_stage.name, to: next_st.name, stats: stats }
  end

  def ranging(game)
    totals = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_total.raw_counters)
    end
    stats = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_stage.raw_counters)
    end
    { type: :ranging, from: game.previous_stage.name, to: 'Ranging', stats: stats, totals: totals }
  end

  def statement_pitched game, statement
    {
      type: :statement_pitched,
      pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      statement: statement.to_s.inspect,
      replaces: statement.to_replace.map{|id| game.current_stage.statements.find(id).try(:statement)}.compact.map(&:inspect)
    }
  end

  def vote_added game, vote
    {
      type: :vote_added,
      voted: vote.player.name,
      result: vote.result
    }
  end

  def vote_timeouts game, statement
    statement.reload
    vote_timeouted_players = (game.players - statement.votes.map(&:player) - begin [game.current_pitcher]; rescue PlayersQueue::ErrorEmptyQueue; [] end).map(&:name)
    { players: vote_timeouted_players, type: :vote_timeouts }
  end

  def statement_results game, statement
    statement.reload
    { statement: statement.to_s.inspect, result: statement.state, total_percents: statement.result, type: :statement_results }
  end

  def pitch_timeout(game)
    pitcher = begin game.current_pitcher; rescue PlayersQueue::ErrorEmptyQueue; nil end
    { pitcher: pitcher ? pitcher.name : '', type: :pitch_timeout }
  end

  def step_results(game)
    stats_data = game.players.inject({}){|r, v| r.merge v.name => v.score.to_player_stat[v.id.to_s].except(:delta).merge(rank: v.score.rank) }
    roles_data = game.current_stage.statements.accepted.inject({}){|r, v| r.merge v.to_s.inspect => v.players_contributions }
    queue_data = game.players_queue.next_pitchers.map(&:name).first(2)
    if game.settings[:random_enabled]
      random_summary = game.players_queue.online_shuffle.data_summary
      random_data = game.players_queue.online_shuffle.data.map{|r| [r[0].to_s, r[1].name, r[2].to_s] }
      Rails.logger.info "---RAND #{random_data.inspect}"
    else
      random_summary = ''
      random_data = []
    end
    {
      type: :step_results,
      stats: stats_data,
      random: random_data,
      random_summary: random_summary,
      roles: roles_data,
      queue: queue_data,
      time_left: time_left(game),
      last_statements_state: game.current_stage.statements.order_by(:created_at.desc).limit(3).map(&:state)
    }
  end

  def delimit(game)
    {type: 'delimit'}
  end

  def next_pitcher(game)
    #FIXME текущего игрока взятого из очереди проверять на живость
    { pitcher: begin game.current_pitcher.try(:name); rescue PlayersQueue::ErrorEmptyQueue; '' end, step: game.current_stage.try(:step), type: :next_pitcher }
  end

  def importance_added game, importance
    { player: importance.player.name, value_raw: importance.value_raw, value: importance.value_name, auto: importance.auto, stage: importance.statement.stage.name, statement: importance.statement.to_s, type: :importance_added }
  end

  def player_connected game, player
    { player: player.name, type: :player_connected }
  end

  def player_disconnected game, player
    { player: player.name, type: :player_disconnected }
  end

  def game_terminated(game)
    {state: :terminated, type: :game_terminated}
  end

  def time_left(game)
    left = if game.settings.stage_timeout
      ((game.current_stage.submission_started_at+game.settings.stage_timeout.seconds-Time.now)/1.second).round
    else
      '<not available>'
    end
  end
end
