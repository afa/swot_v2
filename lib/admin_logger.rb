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
      pitcher: queue.pitcher.name,
      queue: queue.list.first(3).last(2).map(&:name),
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
    stats = players.online.map do |p|
      {
        name: p.name
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
      pitcher: author.name,
      # pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      statement: statement[:value].inspect,
      replaces: voting.replaces.map{|id| statements.find(id).value.inspect}
    }
    push msg
  end

  def vote_added topic, game_id, params = {}
    return unless @guid == game_id
    vote = params[:vote]
    player = Actor[:"player_#{vote[:player]}"]
    return unless player && player.alive?
    state = Actor[:"state_#{@guid}"]
    statements = Actor[:"statements_#{@guid}"]
    msg = {
      subtype: :vote_added,
      voted: player.name,
      result: statements.voting.format_value(vote[:result])
    }
    push msg
  end

  def vote_timeouts topic, game_id, params = {}
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    s_id = params[:statement]
    statements = Actor[:"statements_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    statement = statements.find()
    vote_timeouted_players = (players.online.map(&:uuid) - statement.votes.map(&:player) - [statement.author]).map{|i| players.find(i).name }
    msg = {
      players: vote_timeouted_players,
      subtype: :vote_timeouts
    }
    push msg
  end

  def statement_results topic, game_id, stat_id
    p '-----------------------------', topic, '---------------------------------'
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    statement = statements.find(stat_id)
    msg = {
      statement: statement.value.inspect,
      result: statement.format_value(statement.status),
      total_percents: (statement.result * 100).round(1),
      subtype: :statement_results
    }
    p '+-----------------------------', topic, '---------------------------------'
    push msg
  end

  def pitch_timeout topic, game_id, pitcher_id
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    pitcher = players.find(pitcher_id)
    # pitcher = begin game.current_pitcher; rescue PlayersQueue::ErrorEmptyQueue; nil end
    msg = {
      pitcher: pitcher.name,
      subtype: :pitch_timeout
    }
    push msg
  end

  def step_results topic, game_id, params = {}
    p '-----------------------------', topic, '---------------------------------'
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    queue = Actor[:"queue_#{@guid}"]
    stats_data = players.players.inject({}){|r, v| r.merge v.name => {pitcher: v.pitcher_score, catcher: v.catcher_score, rank: v.pitcher_rank} }
    roles_data = statements.in_stage(state.stage).select{|s| s.status == 'accepted' }.inject({}){|r, v| r.merge v.value.inspect => v.player_contribution }
    queue_data = queue.list.map(&:name).first(3).last(2)
    # if false && state.setting[:random_enabled]
    #   random_summary = game.players_queue.online_shuffle.data_summary
    #   random_data = game.players_queue.online_shuffle.data.map{|r| [r[0].to_s, r[1].name, r[2].to_s] }
    # else
    #   random_summary = ''
    #   random_data = []
    # end
    msg = {
      subtype: :step_results,
      stats: stats_data,
      # random: random_data,
      # random_summary: random_summary,
      roles: roles_data,
      queue: queue_data,
      time_left: Timings::Stage.instance(@guid).next_time,
      last_statements_state: statements.in_stage(state.stage).last(3).map(&:status)
    }
    p '+-----------------------------', topic, '---------------------------------'
    push msg
    info "::::::----------------step_results---------#{msg.inspect}----::::::::::::::::"
  end

  def delimit topic, game_id, params = {}
    return unless @guid == game_id
    msg = {
      subtype: 'delimit'
    }
    push msg
  end

  def next_pitcher topic, game_id, params = {}
    p '-----------------------------', topic, '---------------------------------'
    return unless @guid == game_id
    queue = Actor[:"queue_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    msg = {
      pitcher: queue.pitcher.name,
      step: state.step,
      subtype: :next_pitcher
    }
    push msg
    p '+-----------------------------', topic, '---------------------------------'
  end

  def importance_added topic, game_id, params = {}
    return unless @guid == game_id
    names = ['', 'Not important', 'Rather not important', 'Important', 'Very important', 'Extremely important']
    players = Actor[:"players_#{@guid}"]
    player = players.find(params[:player])
    msg = {
      player: player.name,
      value_raw: params[:value],
      value: names[params[:value].to_i],
      auto: params.fetch(:auto, false),
      stage: State::STAGES[params[:stage].to_sym][:name],
      statement: params[:statement],
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
