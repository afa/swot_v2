class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  include Celluloid::Notifications
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements, :setting

  attr_reader :name, :online
  attr_reader :uuid

  def self.create(params = {})
    uuid = build(params)
    Center.current.async.to_supervise(
      as: :"game_#{uuid}", type: Game,
      args: [
        { uuid: uuid }.merge(params[:server_setup] ? { server_setup: params[:server_setup] } : {}).merge(start: params[:start])
      ]
    )
  end

  def self.build(params = {})
    uuid = UUID.new.generate
    now = Time.now.to_i
    start_at = params[:start_at]
    start_param = params[:start]
    time = if start_at
             Time.at(start_at.to_i).to_i
           elsif start_param
             Time.at(start_param[:time].to_i).to_i
           else
             now + 300
           end

    store = Store::Game.create(
      mongo_id: params[:id],
      name: params[:name],
      uuid: uuid,
      company: params[:company],
      country: params[:country],
      description: params[:description],
      industry: params[:industry],
      state: params[:state],
      time_zone: params[:time_zone],
      start_at: time
    )

    params.fetch(:players, []).each_with_index do |pl, idx|
      dat = pl.merge(game_uuid: uuid, order: idx + 1)
      mid = dat.delete(:id)
      dat[:mongo_id] = mid
      Player.build dat
    end

    sett = Store::Setting.for_game(uuid)
    sett.update data: sett.data.merge(params[:settings]) if params[:settings]
    args = { uuid: uuid, start_at: time }
    args.merge!(params[:server_setup]) if params[:server_setup].is_a?(Hash)
    if store.start_at.to_i > now
      Center.current.to_supervise as: "game_#{uuid}", type: Game, args: [args]
    end
    uuid
  end

  def self.results_for(id)
    store = Store::Game.find(uuid: id).first
    players = Store::Player.find(game_uuid: id).all.to_a
    setting = Store::Setting.find(game_uuid: id).first
    statements = Store::Statement.find(game_uuid: id).all.to_a

    {
      game: { name: store.name, id: store.mongo_id, uuid: store.uuid },
      players: players.map do |player|
        pos = player.position
        scores = player.scores
        {
          name: player.name,
          mangled_name: "Player_#{pos}",
          pitcher_score: scores.pitcher_score,
          catcher_score: scores.catcher_score,
          uuid: player.uuid,
          position: pos
        }
      end,
      settings: setting.data,
      statements: statements.inject(s: [], w: [], o: [], t: []) { |res, sta| }
    }
  end

  def int_state
    Actor[:"state_#{@uuid}"]
  end

  def initialize(params = {})
    @online = false
    @uuid = params[:uuid]
    @server_setup = params[:server_setup]
    sgame = Store::Game.find(uuid: @uuid).first
    @start_at = sgame.start_at
    Center.current.to_supervise as: :"admin_logger_#{@uuid}", type: AdminLogger, args: [{game_uuid: uuid}]
    Center.current.to_supervise as: :"state_#{@uuid}", type: State, args: [{game_uuid: uuid}]

    @name = sgame.name
    state = int_state

    Center.current.to_supervise(as: :"players_#{@uuid}", type: Players, args: [{ game_uuid: @uuid }])
    Center.current.to_supervise as: :"timers_#{@uuid}", type: Timings, args: [{ game_uuid: @uuid }]
    time_start = Timings::Start.instance(@uuid)
    time_start.set_time @start_at
    state.state = if time_start.next_time
                    :waiting
                  elsif time_start.at
                    :started
                  else
                    :waiting
                  end
    # cntrl = Control.current.publish_control( (params.has_key?(:players) ?
    #  {players: players.players.map{|p| {name: p.name, url: "#{@server_setup[:url]}/game/#{p.uuid}",
    #  uuid: p.uuid, email: p.email}}} : {}).merge(type: 'status', uuid: @uuid, replly_to: 'create'))
    Control.current.add_game(@uuid)
    state.add_game @uuid
    subscribe :save_game_data, :save_game_data
    info "done init for #{@uuid}"
    async.run
  end

  def save_game_data(_topic, game_id)
    return unless game_id == uuid
    sync_game
    publish :game_data_saved, uuid, :game
  end

  def sync_game; end

  def onconnect
    push_state reply: 'connect'
  end

  def run
    puts 'ok'
  end

  def start
    state = int_state
    state.clean_state
    players = Actor[:"players_#{uuid}"]
    players.async.build_queue # TODO: move to create
    return unless %w(waiting started).map(&:to_sym).include? state.state
    state.state = :started
    if players.enough_players
      publish :game_started, uuid
      start_stage
    else
      state.state = :terminated
      async.terminate_timeout
    end
  end

  def start_stage # whats?
    players = Actor[:"players_#{uuid}"]
    statements = Actor[:"statements_#{uuid}"]
    Timings::Stage.instance(uuid).start
    statements.clean_current
    players.async.push_start_stage
    async.start_step
  end

  def start_step
    state = int_state
    state.clean_state
    players = Actor[:"players_#{@uuid}"]
    if %w(s w o t).include? state.stage.to_s
      # queue = Actor[:"queue_#{@uuid}"]
      if state.step == 1
        Timings::FirstPitch.instance(@uuid).start
      else
        Timings::Pitch.instance(@uuid).start
      end
      state.step_status = state.first_enum(State::STEP_STATUSES)
    else
      Timings::Ranging.instance(@uuid).start
    end
    players.async.push_start_step
    players.async.push_messages
  end

  def stage_timeout
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    state.stage = state.next_enum(State::STAGES, state.stage)
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    Timings::BetweenStages.instance(@uuid).start
    players.async.push_end_stage
  end

  def ranging(params = {})
    # value index player
    statements = Actor[:"statements_#{uuid}"]
    stage_swot = State::STAGES.fetch(params[:stage], swot: :end)[:swot]
    stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot))
    st = stmnts[params[:index].to_i - 1]
    impo = params.merge(stage: stage_swot, statement: st.value.inspect)
    statements.async.range_for(impo)
    publish :importance_added, uuid, impo
  end

  def pitch(params = {})
    state = int_state
    stage = state.stage
    players = Actor[:"players_#{uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    pitcher = queue.pitcher
    puuid = pitcher.uuid
    value = params[:value]
    return unless state.check_state :pitch, puuid
    state.set_state :pitch, puuid
    statements = Actor[:"statements_#{uuid}"]
    # tm = Time.now.to_i + (state.setting[:voting_quorum_timeout] || 60)
    rpl = (params[:to_replace] || []).map do |repl|
      if repl.is_a? Hash
        repl[:index].to_i
      else
        repl.to_i
      end
    end
    statement = {
      value: value,
      to_replace: rpl,
      author: puuid,
      stage: stage,
      step: state.step,
      game_uuid: uuid
    }
    errors = statements.add statement
    if errors.empty?

      publish :pitcher_pitch, puuid, stage
      state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status)
      Timings::Pitch.instance(uuid).cancel
      Timings::FirstPitch.instance(uuid).cancel
      Timings::VotingQuorum.instance(uuid).start
      publish :statement_pitched, uuid, statement: statement
      players.push_pitch(errors.merge(value: value,
                                      to_replace: params[:to_replace] || [],
                                      author: pitcher.uglify_name(stage.to_s),
                                      timer: Timings.instance(uuid).next_stamp))
    else
      state.clean_state
      pitcher.publish_msg errors
    end
  end

  def pitch_timeout(_params = {})
    queue = Actor[:"queue_#{@uuid}"]
    state = int_state
    pit = queue.pitcher
    pid = pit.uuid
    state.set_state :pitch_end, pid
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    publish :pitch_timeout, @uuid, pid if pit && pit.alive?
    publish :pitcher_timeout, pid, state.stage
    end_step(status: 'timeouted')
  end

  def pass(_params = {})
    queue = Actor[:"queue_#{uuid}"]
    state = int_state
    pit = queue.pitcher_id
    return unless state.check_state(:pass, pit)
    state.set_state :pass, pit
    Timings::Pitch.instance(uuid).cancel
    Timings::FirstPitch.instance(uuid).cancel
    publish :pitcher_passed, pit, state.stage
    publish :pitch_pass, uuid, pit
    end_step(status: 'passed')
  end

  def vote(params = {})
    state = int_state
    players = Actor[:"players_#{uuid}"]
    statements = Actor[:"statements_#{uuid}"]
    voting = statements.voting
    return unless voting
    voting.vote(player: params[:player], result: params[:result])
    publish :vote_added, uuid, vote: { player: params[:player], result: params[:result] }
    if voting.quorum?
      if Timings::VotingQuorum.instance(uuid).next_time.to_f > state.setting[:voting_tail_timeout].to_f
        Timings.instance(uuid).cancel(%w(voting_quorum voting_tail))
        Timings::VotingTail.instance(uuid).start
        players.async.push_quorum
      end
    end
    return unless voting.voted_count == (players.online.map(&:uuid) - [voting.author]).size
    Timings.instance(uuid).cancel(%w(voting_quorum voting_tail))
    async.end_step(status: voting.score.calc_result)
  end

  def end_step_ranging(params)
    players = Actor[:"players_#{uuid}"]
    publish :save_game_data, uuid
    players.async.push_end_step params
    async.end_stage
  end

  def end_step(params = {})
    state = int_state
    players = Actor[:"players_#{uuid}"]
    return end_step_ranging(params) if %w(rs rw ro rt).include? state.stage.to_s
    queue = Actor[:"queue_#{uuid}"]
    statements = Actor[:"statements_#{uuid}"]
    Timings.instance(uuid).cancel(%w(pitch first_pitch voting_quorum voting_tail))
    stat = statements.voting
    stat.process_end_step_voting if stat
    if %w(passed timeouted).include? params[:status]
      queue.pitcher.scores.count_pitcher_score(params[:status] == 'passed' ? 'pass' : params[:status])
    end
    statements.update_visible
    players.async.push_messages
    state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status)
    state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status) unless state.step_status == :end
    Timings::Results.instance(uuid).start unless %w(passed timeouted).include?(params[:status])
    lg = Actor[:"admin_logger_#{uuid}"]
    queue.next
    lg.step_results :step_results, uuid
    lg.statement_results :statement_results, uuid, stat.uuid if stat
    publish :send_score, uuid
    publish :save_game_data, uuid
    players.async.push_end_step params
    async.results_timeout if %w(passed timeouted).include?(params[:status])
  end

  def voting_quorum_timeout(_params = {})
    statements = Actor[:"statements_#{uuid}"]
    voting = statements.voting
    # calc rank results
    Timings::VotingQuorum.instance(uuid).cancel
    Timings::VotingTail.instance(uuid).cancel
    return unless voting
    publish :vote_timeouts, uuid, statement: voting.uuid
    end_step(status: voting.conclusion)
  end

  def voting_tail_timeout(_params = {})
    statements = Actor[:"statements_#{uuid}"]
    Timings::VotingQuorum.instance(uuid).cancel
    Timings::VotingTail.instance(uuid).cancel
    voting = statements.voting
    return unless voting
    publish :vote_timeouts, uuid, statement: voting.uuid
    end_step(status: voting.conclusion)
  end

  def end_stage(_params = {})
    state = int_state
    players = Actor[:"players_#{uuid}"]
    statements = Actor[:"statements_#{uuid}"]
    stage = state.stage = state.next_enum(State::STAGES, state.stage)
    Timings::Terminate.instance(uuid).cancel if stage == :tr
    if %w(sw wo ot tr).include? stage.to_s
      Timings::BetweenStages.instance(uuid).start
      players.async.push_end_stage
      players.copy_half if stage == :sw
      players.copy_before if stage == :tr
      statements.copy_before if stage == :tr
      publish :next_stage, uuid, stage: stage unless stage == :tr
      if stage == :tr
        statements = Actor[:"statements_#{uuid}"]
        statements.init_importances
        publish :ranging, uuid, stage: stage
      end
    elsif %w(rs rw ro rt).include? stage.to_s
      players.async.push_end_stage
      async.start_stage
    elsif stage == :end
      players.async.push_end_stage
      Timings::AfterGame.instance(uuid).start
      players.async.push_game_results
      async.push_saved_game_results
    end
  end

  def end_game(_params = {})
    info 'TODO end game'
    publish :game_done, @uuid
  end

  def results_timeout(_params = {})
    state = int_state
    statements = Actor[:"statements_#{uuid}"]
    # players = Actor[:"players_#{@uuid}"]
    Timings::Results.instance(uuid).cancel
    if statements.check_triple_decline
      async.end_stage
    elsif state.step < state.total_steps
      state.step += 1
      lg = Actor[:"admin_logger_#{uuid}"]
      lg.next_pitcher :next_pitcher, uuid
      async.start_step
    else
      # players = Actor[:"players_#{@uuid}"]
      async.end_stage
    end
  end

  def between_stages_timeout(_params = {})
    state = int_state
    Timings::BetweenStages.instance(@uuid).cancel
    state.stage = state.next_enum(State::STAGES, state.stage)
    state.step = 1
    state.step_status = state.first_enum(State::STEP_STATUSES)

    # check for bugs
    async.start_stage
  end

  def ranging_timeout(_params = {})
    Timings::Ranging.instance(uuid).cancel
    async.end_step
  end

  # def push_event event, params = {}
  #   publish_msg({type: 'event', subtype: event})
  # end

  def push_state(_params = {})
    # state = int_state
    # players = Actor[:"players_#{@uuid}"]
    # msg = params.merge status: state.state, stage: state.stage, timeout_at: Timings::Start.instance(@uuid).at + 1500, started_at: Timings::Start.instance(@uuid).at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    # # msg = params.merge status: state.state, stage: state.stage, timeout_at: alarm.next_time, started_at: alarm.start_at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    # publish_msg msg
  end

  def push_saved_game_results
    sgame = Store::Game.find(uuid: @uuid).first
    hsh = { game_id: sgame.mongo_id }
    statements = Actor[:"statements_#{@uuid}"]
    statements.update_importance_score

    statements.rescore
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    stats = %w(s w o t).map(&:to_sym).inject({}) do |res, sym|
      res[sym] = { statements: [] }
      res[sym][:statements] += statements.visible_for_buf(statements.rebuild_visible_for(sym)).map do |s|
        {
          author: s.author,
          votes: s.votes.map(&:as_json),
          importances: s.importances,
          result: s.result,
          body: s.value,
          contribution: s.score.contribution
        }
      end
      # r[sym][:statements] += statements.visible_for_buf(statements.rebuild_visible_for(sym)).map{|sta| {body: sta.value, contribution: sta.contribution_for(@uuid)} }
      res
    end
    vis = %w(s w o t).map(&:to_sym).inject({}) do |res, sym|
      res[sym] = []
      res[sym] += statements.visible_for_buf(statements.rebuild_visible_for(sym)).map(&:uuid)
      res
    end
    statements.statements.each { |s| s.visible = vis[s.stage.to_sym].include?(s.uuid) }
    sts = statements.statements.map(&:to_store)
    pls = players.players
    ps = pls.map do |pl|
      {
        pl.uglify_name(:s) => {
          name: pl.name,
          pitcher_score: pl.scores.pitcher_score,
          pitcher_score_before_ranging: pl.scores.pitcher_score_before_ranging,
          catcher_score_before_ranging: pl.scores.catcher_score_before_ranging,
          uglify_name: pl.uglify_name(:s),
          pitcher_score_first_half: pl.scores.pitcher_score_first_half,
          catcher_score_first_half: pl.scores.catcher_score_first_half,
          uuid: pl.uuid,
          catcher_score: pl.scores.catcher_score
        }
      }
    end
    hsh.merge! data: stats, players: ps, statements: sts
    al = Actor[:"admin_logger_#{@uuid}"]
    logs = al.as_json
    hsh[:logs] = logs.sort_by { |lg| lg.has_key?(:created_at) ? lg[:created_at] : lg['created_at'] }
    uri = URI(state.setting[:game_results_callback])
    req = Net::HTTP::Post.new uri.request_uri
    req.body = "q='#{hsh.to_json}'"
    rez = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end
    info hsh.inspect
    info rez.inspect
  end

  def stage_timeout
    async.end_stage
  end

  def after_game_timeout
    async.stop_timers
    async.end_game
  end

  def terminate_timeout
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    state.state = :terminated
    publish :game_terminated, @uuid
    # publish_msg({type: 'event', subtype: 'terminated'})
    players.async.push_terminated
    async.stop_timers
    async.end_game
  end

  def stop_timers
    timings = Timings.instance(@uuid)
    timings.async.stop_timers
  end

  def online!
    @online = true
    info "#{@uuid} online"
    # state = Actor[:"state_#{@game_uuid}"]
    # players = Actor[:"players_#{@game_uuid}"]
    # players.check_min_players
    # async.send_ready reply_to: 'connect' if state.state.to_s == 'waiting'
    # async.send_state reply_to: 'connect' if state.state.to_s == 'started'
    # async.send_terminated if state.state.to_s == 'terminated'
    # async.send_result reply_to: 'connect' unless %w(waiting started).include?(state.state.to_s)
    # info 'online'
    # async.publish :player_online, @game_uuid, {uuid: @uuid}
  end

  def offline!
    @online = false
    # players = Actor[:"players_#{@game_uuid}"]
    # players.check_min_players
    info "#{uuid} offline"
    # async.publish :player_offline, @game_uuid, {uuid: @uuid}
  end

  def publish_msg(msg)
    return unless @online
    ch = Actor[:"gm_chnl_#{uuid}"]
    if ch && ch.alive?
      ch.publish_msg msg.to_json
    else
      offline!
    end
  end

  # def publish_msg hash
  #   state = int_state
  #   info "publish game #{hash.inspect}"
  #   # fan = state.game[:fan]
  #   # fan.publish hash.to_json, routing_key: "game.#{@uuid}"
  # end

  def finalizer; end
end
