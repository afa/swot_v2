class AdminLogger
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::IO
  include Celluloid::Internals::Logger

  attr :records, :last_processed

  def initialize(params = {})
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
    subscribe :pitch_pass, :pitch_pass
    subscribe :step_results, :step_results
    subscribe :delimit, :delimit
    subscribe :next_pitcher, :next_pitcher
    subscribe :importance_added, :importance_added
    subscribe :game_terminated, :game_terminated
    subscribe :admin_log_push, :admin_log_push
    subscribe :save_game_data, :save_game_data
    # subscribe :sync_admin_log, :save_game_data
  end

  def push(hash)
    @records << hash.merge(type: :log, created_at: Time.now.to_f.round(6))
    publish :admin_log_push, @guid
  end

  def backup
    info 'TODO admin log backup'
  end

  def restore
    info 'TODO admin log restore'
  end

  def as_json
    sync_admin_log
    store = Store::AdminLog.find(game_uuid: @guid).to_a
    store.map(&:data)

    # @records.map(&:to_hash)
  end

  def save_game_data(topic, game_id)
    return unless game_id == @guid
    sync_admin_log
    publish :game_data_saved, @guid, :admin_log
  end

  def sync_admin_log
    # backup? TODO
    store = Store::AdminLog.find(game_uuid: @guid).sort(by: :created_at).to_a
    rcrds = @records.select { |rec| rec[:redis_id].nil? || !store.any? { |lg| lg.id == rec[:redis_id] } }
    rcrds.each do |rc|
      r = Store::AdminLog.create game_uuid: @guid, data: rc, created_at: rc[:created_at]
      rc[:redis_id] = r.id
    end
  end

  def game_started(_topic, game_id, _params = {})
    # TODO: fix rescue and game methods
    return unless @guid == game_id
    queue = Actor[:"queue_#{@guid}"]
    lst = queue.list.first(3)
    pit = lst.shift
    msg = {
      subtype: :start,
      pitcher: pit.name,
      queue: lst.map(&:name),
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
    queue = Actor[:"queue_#{@guid}"]
    lst = queue.list.first(3)
    pit = lst.shift
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
      pitcher: pit.name,
      queue: lst.map(&:name),
      time_left: Timings::Stage.instance(@guid).next_time,
      to: state.stage_name
      # stats: stats
    }
    push msg
  end

  def ranging(_topic, game_id, _params = {})
    return unless @guid == game_id
    state = Actor[:"state_#{@guid}"]
    # TODO: restore when calc online statistics done
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

  def statement_pitched(_topic, game_id, params = {})
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    statement = params[:statement]
    statements = Actor[:"statements_#{@guid}"]
    voting = statements.voting # TODO: оставлять или нет непонятно. возможно нужно передать замены отдельно и урезать.
    author = players.find(statement[:author])
    return unless author && author.alive?
    msg = {
      subtype: :statement_pitched,
      pitcher: author.name,
      # pitcher: begin game.current_pitcher.name; rescue PlayersQueue::ErrorEmptyQueue; '' end,
      statement: statement[:value].inspect,
      replaces: voting.replaces.map { |id| statements.find(id).value.inspect }
    }
    push msg
  end

  def vote_added(_topic, game_id, params = {})
    return unless @guid == game_id
    vote = params[:vote]
    player = Actor[:"player_#{vote[:player]}"]
    return unless player && player.alive?
    statements = Actor[:"statements_#{@guid}"]
    msg = {
      subtype: :vote_added,
      voted: player.name,
      result: statements.voting.format_value(vote[:result])
    }
    push msg
  end

  def vote_timeouts(_topic, game_id, params = {})
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    s_id = params[:statement]
    statements = Actor[:"statements_#{@guid}"]
    statement = statements.find(s_id)
    vote_timeouted_players = (statement.votable - statement.votes.map(&:player)).map { |item| players.find(item).name }
    msg = {
      players: vote_timeouted_players,
      subtype: :vote_timeouts
    }
    push msg
  end

  def statement_results(_topic, game_id, stat_id)
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    statement = statements.find(stat_id)
    stat_res = statement.result * 100.0
    stat_res = 100.0 - stat_res unless statement.status == 'accepted'
    msg = {
      statement: statement.value.inspect,
      result: statement.status,
      # result: statement.format_value(statement.status),
      total_percents: !statement.quorum? ? 'no quorum' : stat_res.round(1),
      # total_percents: stat_res.round(1),
      subtype: :statement_results
    }
    push msg
  end

  def pitch_pass(_topic, game_id, pitcher_id)
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    pitcher = players.find(pitcher_id)
    msg = {
      pitcher: pitcher.name,
      subtype: :pitch_passed
    }
    push msg
  end

  def pitch_timeout(_topic, game_id, pitcher_id)
    return unless @guid == game_id
    players = Actor[:"players_#{@guid}"]
    pitcher = players.find(pitcher_id)
    msg = {
      pitcher: pitcher.name,
      subtype: :pitch_timeout
    }
    push msg
  end

  def step_results(_topic, game_id, params = {})
    return unless @guid == game_id
    statements = Actor[:"statements_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    queue = Actor[:"queue_#{@guid}"]
    stats_data = players.players.inject({}) do |r, v|
      r.merge v.name => {
        pitcher: format('%.03f', v.pitcher_score.to_f),
        catcher: format('%.01f', v.catcher_score),
        rank: format('%.03f', v.pitcher_rank)
      }
    end
    roles_data = statements.visible_for_buf(statements.rebuild_visible_for(state.stage)).inject({}) do |rez, vl|
      rez.merge(vl.value.inspect => vl.player_contribution.inject({}) do |res, (key, val)|
        res.merge(key => format('%.03f', val))
      end)
    end
    # roles_data = statements.in_stage(state.stage).select{|s| s.status == 'accepted' }.inject({}){|r, v|
    # r.merge(v.value.inspect => (v.player_contribution.inject({}){|res, (key, val)| res.merge(key => format('%.03f',
    # val)) } )) }
    queue_data = queue.list.map(&:name).first(2)
    # queue_data = queue.list.map(&:name).first(3).last(2) ## CHECK спешка очереди на 1
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
    push msg
  end

  def delimit(_topic, game_id, _params = {})
    return unless @guid == game_id
    msg = {
      subtype: 'delimit'
    }
    push msg
  end

  def next_pitcher(_topic, game_id, _params = {})
    return unless @guid == game_id
    queue = Actor[:"queue_#{@guid}"]
    state = Actor[:"state_#{@guid}"]
    msg = {
      pitcher: queue.pitcher.name,
      step: state.step,
      subtype: :next_pitcher
    }
    push msg
  end

  def importance_added(_topic, game_id, params = {})
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

  def game_terminated(_topic, game_id, _params = {})
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

  def player_offline(_topic, game_id, params = {})
    return unless @guid == game_id
    player = Actor[:"player_#{params[:uuid]}"]
    return unless player
    info "----------------------player #{params[:uuid]} (#{player.name}) (#{topic}) offline----------------------------"
    msg = {
      subtype: :player_disconnected,
      player: player.name
    }
    push msg
  end
end
