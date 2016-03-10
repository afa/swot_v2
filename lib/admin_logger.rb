class AdminLogger
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::IO
  include Celluloid::Internals::Logger

  attr :records, :last_saved
  def initialize params = {}
    @guid = params[:game_uuid]
    @records = []
    subscribe :player_online, :player_online
    subscribe :player_offline, :player_offline
    subscribe :game_started, :game_started
    subscribe :next_stage, :next_stage
    subscribe :ranging, :ranging
  end

  def push hash
    @records << hash.merge(type: :log, created_at: Time.now.to_f.round(6))
  end

  def backup
  end

  def restore
  end

  def game_started topic, game_id, params = {}
    return unless @guid == game_id
    { 
      subtype: :start,
      pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      queue: begin [ game.players_queue.current_pitcher.name ]; rescue PlayersQueue::ErrorEmptyQueue; [] end + game.players_queue.next_pitchers.map(&:name),
      time_left: time_left(game)
    }
  end

  def next_stage topic, game_id, params = {}
    return unless @guid == game_id
    stats = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_stage.raw_counters)
    end
    {
      type: :next_stage,
      from: game.previous_stage.name,
      to: next_st.name,
      stats: stats
    }
  end

  
  def ranging topic, game_id, params = {}
    return unless @guid == game_id
    totals = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_total.raw_counters)
    end
    stats = game.players.active.map do |p|
      { name: p.name }.merge(p.stats_stage.raw_counters)
    end
    {
      type: :ranging,
      from: game.previous_stage.name,
      to: 'Ranging',
      stats: stats,
      totals: totals
    }
  end

  def statement_pitched topic, game_id, params = {}
    return unless @guid == game_id
    statement = params[:statement]
    {
      type: :statement_pitched,
      pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      statement: statement.to_s.inspect,
      replaces: statement.to_replace.map{|id| game.current_stage.statements.find(id).try(:statement)}.compact.map(&:inspect)
    }
  end

  def vote_added topic, game_id, params = {}
    return unless @guid == game_id
    vote = params[:vote]
    {
      type: :vote_added,
      voted: vote.player.name,
      result: vote.result
    }
  end

  def vote_timeouts topic, game_id, params = {}
    return unless @guid == game_id
    vote_timeouted_players = (game.players - statement.votes.map(&:player) - begin [game.current_pitcher]; rescue PlayersQueue::ErrorEmptyQueue; [] end).map(&:name)
    {
      players: vote_timeouted_players,
      type: :vote_timeouts
    }
  end

  def statement_results topic, game_id, params = {}
    return unless @guid == game_id
    {
      statement: statement.to_s.inspect,
      result: statement.state,
      total_percents: statement.result,
      type: :statement_results
    }
  end

  def pitch_timeout topic, game_id, params = {}
    return unless @guid == game_id
    pitcher = begin game.current_pitcher; rescue PlayersQueue::ErrorEmptyQueue; nil end
    {
      pitcher: pitcher ? pitcher.name : '',
      type: :pitch_timeout
    }
  end

  def step_results topic, game_id, params = {}
    return unless @guid == game_id
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

  def delimit topic, game_id, params = {}
    return unless @guid == game_id
    {
      type: 'delimit'
    }
  end

  def next_pitcher topic, game_id, params = {}
    return unless @guid == game_id
    {
      pitcher: begin game.current_pitcher.try(:name); rescue PlayersQueue::ErrorEmptyQueue; '' end,
      step: game.current_stage.try(:step),
      type: :next_pitcher
    }
  end

  def importance_added topic, game_id, params = {}
    return unless @guid == game_id
    {
      player: importance.player.name,
      value_raw: importance.value_raw,
      value: importance.value_name,
      auto: importance.auto,
      stage: importance.statement.stage.name,
      statement: importance.statement.to_s,
      type: :importance_added
    }
  end

  def game_terminated topic, game_id, params = {}
    return unless @guid == game_id
    {
      state: :terminated,
      type: :game_terminated
    }
  end

  def player_online topic, game_id, params = {}
    return unless @guid == game_id
    info "----------------------player #{params[:uuid]} (#{topic}) online----------------------------"
    {
      subtype: :player_connected,
      player: player.name
    }
  end

  def player_offline topic, game_id, params = {}
    return unless @guid == game_id
    info "----------------------player #{params[:uuid]} (#{topic}) offline----------------------------"
    {
      subtype: :player_disconnected,
      player: player.name
    }
  end

end
