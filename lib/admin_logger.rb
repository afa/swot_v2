class AdminLogger
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::IO
  include Celluloid::Internals::Logger

  attr :records, :last_processed
  def initialize params = {}
    @guid = params[:game_uuid]
    @records = []
    @last_processed = 0
    subscribe :admin_channel_connected, :resend_log
    subscribe :player_online, :player_online
    subscribe :player_offline, :player_offline
    subscribe :game_started, :game_started
    subscribe :next_stage, :next_stage
    subscribe :ranging, :ranging
    subscribe :statement_pitched, :statement_pitched
    subscribe :vote_added, :vote_added
    subscribe :vote_timeouts, :vote_timeouts
    subscribe :statement_results, :statement_results
    subscribe :pitch_timeout, :pitch_timeout
    subscribe :step_results, :step_results
    subscribe :delimit, :delimit
    subscribe :next_pitcher, :next_pitcher
    subscribe :importance_added, :importance_added
    subscribe :game_terminated, :game_terminated
    subscribe :admin_log_push, :admin_log_push
    subscribe :save_game_data, :save_game_data
  end

  def push hash
    @records << hash.merge(type: :log, created_at: Time.now.to_f.round(6))
    publish :admin_log_push, @guid
  end

  def backup
    info 'TODO admin log backup'
  end

  def restore
    info 'TODO admin log restore'
  end

  def save_game_data topic, game_id
    return unless game_id == @guid
    sync_admin_log
    publish :game_data_saved, @guid, :admin_log
  end

  def sync_admin_log
    info 'syncing admin_log'
  end

  def publish_msg msg
    ch = Actor[:"gm_chnl_#{@guid}"]
    if ch && ch.alive?
      ch.publish_msg msg.to_json
    end
  end

  def resend_log topic, game_id
    return unless @guid == game_id
    msg = {
      type: :logs,
      values: @records[0, @last_processed]
    }
    publish_msg msg
    info msg.inspect
  end

  def admin_log_push topic, game_id
    return unless @guid == game_id
    cnt = @records.size - @last_processed
    return if 0 == cnt
    game = Actor[:"game_#{@guid}"]
    unless game && game.alive? && game.online
      info "admin_log_push TODO game offline"
      
      return
    end
    @records[-cnt..-1].each do |rcrd|
      publish_msg rcrd
    end
    @last_processed += cnt
  end

  def game_started topic, game_id, params = {}
    # TODO fix rescue and game methods
    return unless @guid == game_id
    state = Actor[:"state_#{@guid}"]
    queue = Actor[:"queue_#{@guid}"]
    msg = {
      subtype: :start,
      pitcher: queue.pitcher.uglify_name(state.stage.to_s),
      queue: [ queue.pitcher.uglify_name(state.stage.to_s) ] + queue.list.first(2).map{|p| p.uglify_name(state.stage) },
      time_left: Timings::Stage.instance(@guid).next_time
    }
    push msg
  end

  def next_stage topic, game_id, params = {}
    return unless @guid == game_id
    # TODO statistics
    # stage: sym

    state = Actor[:"state_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    stats = players.players.online.map do |p|
      {
        name: p.uglify_name(state.stage)
      }
      # .merge(
      #   p.stats_stage.raw_counters
      # )
    end
    msg = {
      subtype: :next_stage,
      from: state.previous_stage_name,
      to: state.stage_name
      # stats: stats
    }
    push msg
  end

  
  def ranging topic, game_id, params = {}
    return unless @guid == game_id
    state = Actor[:"state_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    # TODO restore when calc online statistics done
    # totals = players.players.select(&:online).map do |p|
    #   { name: p.name }.merge(p.stats_total.raw_counters)
    # end
    # stats = players.players.select(&:online).map do |p|
    #   { name: p.name }.merge(p.stats_stage.raw_counters)
    # end
    msg = {
      subtype: :ranging,
      from: state.previous_stage_name,
      # stats: stats,
      # totals: totals,
      to: 'Ranging'
    }
    push msg
  end

  def statement_pitched topic, game_id, params = {}
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    statement = params[:statement]
    statements = Actor[:"statements_#{@guid}"]
    voting = statements.voting #TODO оставлять или нет непонятно. возможно нужно передать замены отдельно и урезать.
    author = players.find(statement[:author])
    return unless author && author.alive?
    msg = {
      subtype: :statement_pitched,
      pitcher: author.uglify_name(state.stage),
      # pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      statement: statement[:value],
      replaces: voting.replaces.map{|id| statements.find(id).value}
    }
    push msg
  end

  def vote_added topic, game_id, params = {}
    return unless @guid == game_id
    vote = params[:vote]
    player = Actor[:"player_#{vote[:player]}"]
    return unless player && player.alive?
    state = Actor[:"state_#{@uuid}"]
    msg = {
      subtype: :vote_added,
      voted: player.uglify_name(state.stage),
      result: vote[:result]
    }
    push msg
  end

  def vote_timeouts topic, game_id, params = {}
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    s_id = params[:statement]
    statements = Actor[:"statements_#{@guid}"]
    statement = statements.find()
    vote_timeouted_players = (players.online.map(&:uuid) - statement.votes.map(&:player) - [statement.author]).map{|i| players.find(i). }
    msg = {
      players: vote_timeouted_players,
      subtype: :vote_timeouts
    }
    push msg
  end

  def statement_results topic, game_id, stat_id
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    statement = statements.find(stat_id)
    msg = {
      statement: statement.value.inspect,
      result: statement.status,
      total_percents: statement.result,
      subtype: :statement_results
    }
    push msg
  end

  def pitch_timeout topic, game_id, pitcher_id
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    pitcher = players.find(pitcher_id)
    # pitcher = begin game.current_pitcher; rescue PlayersQueue::ErrorEmptyQueue; nil end
    msg = {
      pitcher: pitcher.uglify_name(state.stage),
      subtype: :pitch_timeout
    }
    push msg
  end

  def step_results topic, game_id, params = {}
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    queue = Actor[:"queue_#{@guid}"]
    # stats_data = game.players.inject({}){|r, v| r.merge v.name => v.score.to_player_stat[v.id.to_s].except(:delta).merge(rank: v.score.rank) }
    stats_data = {} #TODO fix stats
    roles_data = statements.in_stage(state.stage).select{|s| s.status == 'accepted' }.inject({}){|r, v| r.merge v.value.inspect => v.contribution }
    queue_data = queue.list.mapi{|p| p.uglify_name(state.stage) }.first(2)
    if false && state.setting[:random_enabled]
      random_summary = game.players_queue.online_shuffle.data_summary
      random_data = game.players_queue.online_shuffle.data.map{|r| [r[0].to_s, r[1].name, r[2].to_s] }
    else
      random_summary = ''
      random_data = []
    end
    msg = {
      subtype: :step_results,
      stats: stats_data,
      random: random_data,
      random_summary: random_summary,
      roles: roles_data,
      queue: queue_data,
      time_left: Timings::Stage.instance(@guid).next_time,
      last_statements_state: statements.in_stage(state.stage).last(3).map(&:status)
    }
    push msg
  end

  def delimit topic, game_id, params = {}
    return unless @guid == game_id
    msg = {
      subtype: 'delimit'
    }
    push msg
  end

  def next_pitcher topic, game_id, params = {}
    return unless @guid == game_id
    queue = Actor[:"queue_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    msg = {
      pitcher: queue.pitcher.uglify_name(state.stage),
      step: state.step,
      subtype: :next_pitcher
    }
    push msg
  end

  def importance_added topic, game_id, params = {}
    return
    return unless @guid == game_id
    msg = {
      player: importance.player.name,
      value_raw: importance.value_raw,
      value: importance.value_name,
      auto: importance.auto,
      stage: importance.statement.stage.name,
      statement: importance.statement.to_s,
      subtype: :importance_added
    }
    push msg
  end

  def game_terminated topic, game_id, params = {}
    return unless @guid == game_id
    msg = {
      state: :terminated,
      subtype: :game_terminated
    }
    push msg
  end

  def player_online topic, game_id, params = {}
    return unless @guid == game_id
    player = Actor[:"player_#{params[:uuid]}"]
    return unless player
    return unless player.alive?
    info "----------------------player #{player.uuid} (#{player.name}) online----------------------------"
    msg = {
      subtype: :player_connected,
      player: player.name
    }
    push msg
  end

  def player_offline topic, game_id, params = {}
    return unless @guid == game_id
    player = Actor[:"player_#{params[:uuid]}"]
    return unless player
    info "----------------------player #{params[:uuid]} (#{topic}) offline----------------------------"
    msg = {
      subtype: :player_disconnected,
      player: player.name
    }
    push msg
  end

end
