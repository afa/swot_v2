class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  include Celluloid::Notifications
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements, :setting

  attr_accessor :name, :online

  def self.create params = {}
    uuid = build(params)
    Center.current.async.to_supervise as: :"game_#{uuid}", type: Game, args: [{uuid: uuid}.merge(params[:server_setup] ? {server_setup: params[:server_setup]} : {}).merge(start: params[:start])]
  end

  def self.build params = {}
    uuid = UUID.new.generate

    store = Store::Game.create({
      mongo_id: params[:id],
      name: params[:name],
      uuid: uuid,
      company: params[:company],
      country: params[:country],
      description: params[:description],
      industry: params[:industry],
      state: params[:state],
      time_zone: params[:time_zone],
      start_at: params[:start_at]
    })

    if params[:players]
      params[:players].each do |pl|
        dat = pl.merge(game_uuid: uuid)
        mid = dat.delete(:id)
        dat.merge!(mongo_id: mid)
        Player.build dat
      end
    end

    sett = Store::Setting.for_game(uuid)
    if params[:settings]
      sett.update data: sett.data.merge(params[:settings])
    end

    uuid
  end

  def int_state
    Actor[:"state_#{@uuid}"]
  end

  def initialize params = {}
    @online = false
    @uuid = params[:uuid]
    @server_setup = params[:server_setup]
    info "#{@uuid} created"
    sett = {settings: params[:settings]} if params[:settings] && !params[:settings].empty?
    sett ||= {}
    p 'settings', sett
    Center.current.to_supervise as: :"admin_logger_#{@uuid}", type: AdminLogger, args: [{game_uuid: @uuid}]
    Center.current.to_supervise as: :"state_#{@uuid}", type: State, args: [{game_uuid: @uuid}.merge(sett)]
    time_params = {}
    if params[:start]
      time_params.merge!(start: params[:start][:time].to_i) if params[:start][:time]
      @timezone = params[:start][:time_zone]
    end
      
    self.name = params[:name]
    state = int_state

    Center.current.to_supervise(as: :"players_#{@uuid}", type: Players, args: [{game_uuid: @uuid}])
    players = Actor[:"players_#{@uuid}"]
    pl_list = Store::Player.find(game_uuid: @uuid).to_a
      pl_list.each do |p|
        p_id = p.uuid
        Center.current.to_supervise(as: :"player_#{p_id}", type: Player, args: [{game_uuid: @uuid, uuid: p_id}])
        players.async.add p_id
      end
    timers = Center.current.to_supervise as: :"timers_#{@uuid}", type: Timings, args: [{game_uuid: @uuid}.merge(time_params)]
    p Timings::Start.instance(@uuid).set_time params[:start][:time]
    state.state = Timings::Start.instance(@uuid).next_time ? :waiting : Timings::Start.instance(@uuid).at ? :started : :waiting
    cntrl = Control.current.publish_control( (params.has_key?(:players) ? {players: players.players.map{|p| {name: p.name, url: "#{@server_setup[:url]}/game/#{p.uuid}", uuid: p.uuid, email: p.email}}} : {}).merge(type: 'status', uuid: @uuid, replly_to: 'create'))
    Control.current.add_game(@uuid)
    state.add_game @uuid
    subscribe :save_game_data, :save_game_data
    p players.players.map(&:uuid)
    async.run
  end

  def save_game_data topic, game_id
    return unless game_id == @uuid
    sync_game
    publish :game_data_saved, @uuid, :game
  end

  def sync_game
    info 'syncing game'
  end

  def onconnect
    push_state reply: 'connect'
  end

  def run
    p @uuid
    puts 'ok'
  end

  def start
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    players.async.build_queue # TODO move to create
    if %w(waiting started).map(&:to_sym).include? state.state
      state.state = :started
      if players.enough_players
        publish :game_started, @uuid
        start_stage
      else
        state.state = :terminated
        async.terminate_timeout
      end
    end
  end

  def start_stage #whats?
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    Timings::Stage.instance(@uuid).start
    statements.clean_current
    # async.publish_msg(type: 'event', subtype: 'start_stage', value: stage)
    players.async.push_start_stage
    async.start_step
  end

  def start_step
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    if %w(s w o t).include? state.stage.to_s
      queue = Actor[:"queue_#{@uuid}"]
      info "start step step = #{state.step}"
      if state.step == 1
        Timings::FirstPitch.instance(@uuid).start
      else
        Timings::Pitch.instance(@uuid).start
      end
      state.step_status = state.first_enum(State::STEP_STATUSES)
    else
      Timings::Ranging.instance(@uuid).start
    end
    # async.publish_msg(type: 'event', subtype: 'start_step')
    players.async.push_start_step
    # async.push_state
    players.async.push_state
  end

  def stage_timeout
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    info "stage timeout: #{state.stage}"
    state.stage = state.next_enum(State::STAGES, state.stage)
    # msg = {type: 'event', subtype: 'end_stage', value: state.stage}
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    Timings::BetweenStages.instance(@uuid).start
    # async.publish_msg msg
    players.async.push_end_stage
  end

  def ranging params = {}
    # value index player
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    stage_swot = State::STAGES.fetch(params[:stage], {swot: :end})[:swot]
    p 'stswot', stage_swot, params
    stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot))
    p stmnts
    st = stmnts[params[:index].to_i - 1]
    impo = { player: params[:player], value: params[:value], index: params[:index], stage: stage_swot, statement: st.value.inspect }
    statements.async.range_for(impo)
    publish :importance_added, @uuid, impo
  end

  def pitch params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    tm = Time.now.to_i + (state.setting[:voting_quorum_timeout] || 60)
    statement = {value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uuid, stage: state.stage, step: state.step, game_uuid: @uuid}
    errors = statements.add statement
    state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status)
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    Timings::VotingQuorum.instance(@uuid).start
    publish :statement_pitched, @uuid, statement: statement
    players.push_pitch(errors.merge(value: params[:value], to_replace: params[:to_replace] || [], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Timings.instance(@uuid).next_stamp))
    # publish_msg({type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Timings.instance(@uuid).next_stamp}.merge(errors))
    unless errors.empty?
      end_step(errors)
    end
  end

  def pitch_timeout params = {}
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    queue = Actor[:"queue_#{@uuid}"]
    p = queue.pitcher
    publish :pitch_timeout, @uuid, p.uuid if p && p.alive?
    end_step(status: 'timeouted')

  end

  def pass params = {}
    info "PASS!"
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    end_step(status: 'passed')
  end

  def vote params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    statements.voting.vote(player: params[:player], result: params[:result])
    publish :vote_added, @uuid, vote: {player: params[:player], result: params[:result]}
    if statements.voting.quorum?
      if Timings::VotingQuorum.instance(@uuid).next_time.to_f > state.setting[:voting_tail_timeout].to_f
        Timings.instance(@uuid).cancel(%w(voting_quorum voting_tail))
        Timings::VotingTail.instance(@uuid).start
        # async.publish_msg(type: 'event', subtype: 'quorum', timeout_at: Timings.instance(@uuid).next_stamp)
        players.async.push_quorum
      end
    end
    if statements.voting.voted_count == (players.online.map(&:uuid) - [statements.voting.author] ).size
        Timings.instance(@uuid).cancel(%w(voting_quorum voting_tail))
      async.end_step(status: statements.voting.calc_result)
    end
  end

  def end_step params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    if %w(rs rw ro rt).include? state.stage.to_s
      # msg = {type: 'event', subtype: 'end_step', timer: Timings.instance(@uuid).next_stamp}
      # async.publish_msg msg
      players.async.push_end_step params
      async.end_stage
    else
      queue = Actor[:"queue_#{@uuid}"]
      statements = Actor[:"statements_#{@uuid}"]
      Timings.instance(@uuid).cancel(%w(pitch first_pitch voting_quorum voting_tail))
      stat = statements.voting
      if stat
        stat.calc_votes
        stat.vote_results!
        publish :player_log_push, @uuid, stat.uuid
      end
      statements.update_visible
      # async.push_state
      players.async.push_messages
      state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status)
      state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status) unless state.step_status == :end
      Timings::Results.instance(@uuid).start unless %w(passed timeouted).include?(params[:status])
      p 'stat', stat
      lg = Actor[:"admin_logger_#{@uuid}"]
      queue.next!
      lg.step_results :step_results, @uuid
      # publish :step_results, @uuid
      lg.statement_results :statement_results, @uuid, stat.uuid if stat
      # publish :statement_results, @uuid, stat.uuid if stat
      # publish :next_pitcher, @uuid
      # lg.send_score :send_score, @uuid
      publish :send_score, @uuid
      # info '------------------------------------66666666666---------------------------'
      # msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: 0, delta: 0}, timer: Timings.instance(@uuid).next_stamp}
      # info '------------------------------------77777777777---------------------------'
      # async.publish_msg msg
      players.async.push_end_step params
      async.results_timeout if %w(passed timeouted).include?(params[:status])
    end
  end

  def voting_quorum_timeout params = {}
    # state = int_state
    # players = Actor[:"players_#{@uuid}"]
    # queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    #calc rank results
    Timings::VotingQuorum.instance(@uuid).cancel
    Timings::VotingTail.instance(@uuid).cancel
    publish :vote_timeouts, @uuid, {statement: statements.voting.uuid}
    end_step(status: statements.voting.conclusion)
  end

  def voting_tail_timeout params = {}
    statements = Actor[:"statements_#{@uuid}"]
    Timings::VotingQuorum.instance(@uuid).cancel
    Timings::VotingTail.instance(@uuid).cancel
    publish :vote_timeouts, @uuid, {statement: statements.voting.uuid}
    end_step(status: statements.voting.conclusion)
  end

  def end_stage params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # queue = Actor[:"queue_#{@uuid}"]
    # statements = Actor[:"statements_#{@uuid}"]
    state.stage = state.next_enum(State::STAGES, state.stage)
    Timings::Terminate.instance(@uuid).cancel if state.stage == :tr
    if %w(sw wo ot tr).include? state.stage.to_s
      Timings::BetweenStages.instance(@uuid).start
      # msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Timings.instance(@uuid).next_stamp}
      # async.publish_msg msg
      players.async.push_end_stage
      publish :next_stage, @uuid, stage: state.stage unless state.stage == :tr
      publish :ranging, @uuid, stage: state.stage if state.stage == :tr
    elsif %w(rs rw ro rt).include? state.stage.to_s
      # msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Time.now.to_i + 1}
      # async.publish_msg msg
      players.async.push_end_stage
      async.start_stage
    elsif state.stage == :end
      async.end_game
    end
  end

  def end_game params = {}
    info 'TODO end game'
    publish :game_done, @uuid
  end

  def results_timeout params = {}
    state = int_state
    statements = Actor[:"statements_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    Timings::Results.instance(@uuid).cancel
    if statements.check_triple_decline
      async.end_stage
    else
      p '====================step====================', state.step, '======================'
      if state.step < state.total_steps
        state.step += 1
        lg = Actor[:"admin_logger_#{@uuid}"]
        info '------------------------------------44444444444---------------------------'
        lg.next_pitcher :next_pitcher, @uuid
        async.start_step
      else
        players = Actor[:"players_#{@uuid}"]
        async.end_stage
      end
    end
  end

  def between_stages_timeout params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    Timings::BetweenStages.instance(@uuid).cancel
    state.stage = state.next_enum(State::STAGES, state.stage)
    state.step = 1
    state.step_status = state.first_enum(State::STEP_STATUSES)

    # check for bugs
    async.start_stage
  end

  def ranging_timeout params = {}
    Timings::Ranging.instance(@uuid).cancel
    async.end_step
    # end_stage
  end

  # def push_event event, params = {}
  #   publish_msg({type: 'event', subtype: event})
  # end

  def push_state params = {}
    # state = int_state
    # players = Actor[:"players_#{@uuid}"]
    # msg = params.merge status: state.state, stage: state.stage, timeout_at: Timings::Start.instance(@uuid).at + 1500, started_at: Timings::Start.instance(@uuid).at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    # # msg = params.merge status: state.state, stage: state.stage, timeout_at: alarm.next_time, started_at: alarm.start_at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    # publish_msg msg
  end

  def stage_timeout
    async.end_stage
  end

  def terminate_timeout
    info 'terminate_timeout'
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
    info "#{@uuid} offline"
    # async.publish :player_offline, @game_uuid, {uuid: @uuid}
  end

  def publish_msg msg
    if @online
      ch = Actor[:"gm_chnl_#{@uuid}"]
      if ch && ch.alive?
        p 'game chnl ok'
        ch.publish_msg msg.to_json
      else
        p 'chnl down'
        offline!
      end
    else
      info "game #{@uuid} offline"
    end
    info msg.inspect
  end

  # def publish_msg hash
  #   state = int_state
  #   info "publish game #{hash.inspect}"
  #   # fan = state.game[:fan]
  #   # fan.publish hash.to_json, routing_key: "game.#{@uuid}"
  # end

  def finalizer
    # Center.current.delete(:"alarms_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @alarms.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
