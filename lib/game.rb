class Game
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  extend Forwardable
  finalizer :finalizer
  def_delegators :int_state, :stage, :step, :total_steps, :step_status, :statements, :setting

  attr_accessor :name
  def self.create params = {}
    uuid = UUID.new.generate
    Center.current.async.to_supervise as: :"game_#{uuid}", type: Game, args: [{uuid: uuid}.merge(params)]
  end

  def int_state
    Actor[:"state_#{@uuid}"]
  end

  def initialize params = {}
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
    state = Actor[:"state_#{@uuid}"]

    Center.current.to_supervise(as: :"players_#{@uuid}", type: Players, args: [{game_uuid: @uuid}])
    players = Actor[:"players_#{@uuid}"]
    if params[:players]
      params[:players].each do |p|
        p_id = UUID.new.generate
        Center.current.to_supervise(as: :"player_#{p_id}", type: Player, args: [p.merge(game_uuid: @uuid, uuid: p_id)])
        players.async.add p_id
      end
    end
    timers = Center.current.to_supervise as: :"timers_#{@uuid}", type: Timings, args: [{game_uuid: @uuid}.merge(time_params)]
    p Timings::Start.instance(@uuid).set_time params[:start][:time]
    state.state = Timings::Start.instance(@uuid).next_time ? :waiting : Timings::Start.instance(@uuid).at ? :started : :waiting
    cntrl = Control.current.publish_control( (params.has_key?(:players) ? {players: players.players.map{|p| {name: p.name, url: "#{@server_setup[:url]}/game/#{p.uuid}", uuid: p.uuid, email: p.email}}} : {}).merge(type: 'status', uuid: @uuid, replly_to: 'create'))
    Control.current.add_game(@uuid)
    state.add_game @uuid
    async.run
  end

  def onconnect
    push_state reply: 'connect'
  end

  def run
    p @uuid
    puts 'ok'
  end

  def start
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    players.async.build_queue # TODO move to create
    if %w(waiting started).map(&:to_sym).include? state.state
      state.state = :started
      if players.enough_players
        start_stage
      else
        state.state = :terminated
        async.terminate_timeout
      end
    end
  end

  def start_stage #whats?
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    Timings::Stage.instance(@uuid).start
    statements.clean_current
    async.publish_msg(type: 'event', subtype: 'start_stage', value: stage)
    players.async.push_start_stage
    async.start_step
  end

  def start_step
    state = Actor[:"state_#{@uuid}"]
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
    async.publish_msg(type: 'event', subtype: 'start_step')
    players.async.push_start_step
    async.push_state
    players.async.push_state
  end

  def stage_timeout
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    info "stage timeout: #{state.stage}"
    state.stage = state.next_enum(State::STAGES, state.stage)
    msg = {type: 'event', subtype: 'end_stage', value: state.stage}
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    Timings::BetweenStages.instance(@uuid).start
    async.publish_msg msg
    players.async.push_end_stage
  end

  def ranging params = {}
    # value index player
    info 'TODO ranging'
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    statements.async.range_for(player: params[:player], value: params[:value], index: params[:index], stage: State::STAGES[state.stage][:swot])
  end

  def pitch params = {}
    state = Actor[:"state_#{@uuid}"]
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
    players.push_pitch(errors.merge(value: params[:value], to_replace: params[:to_replace] || [], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Timings.instance(@uuid).next_stamp))
    publish_msg({type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Timings.instance(@uuid).next_stamp}.merge(errors))
    unless errors.empty?
      end_step(errors)
    end
  end

  def pitch_timeout params = {}
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    end_step(status: 'timeouted')

  end

  def pass params = {}
    info "PASS!"
    Timings::Pitch.instance(@uuid).cancel
    Timings::FirstPitch.instance(@uuid).cancel
    end_step(status: 'passed')
  end

  def vote params = {}
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    statements.voting.vote(player: params[:player], result: params[:result])
    if statements.voting.voted_count == players.players.size - 1
      Timings::VotingQuorum.instance(@uuid).cancel
      end_step(status: statements.voting.calc_result)
    end
  end

  def end_step params = {}
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    if %w(rs rw ro rt).include? state.stage.to_s
      msg = {type: 'event', subtype: 'end_step', timer: Timings.instance(@uuid).next_stamp}
      async.publish_msg msg
      players.async.push_end_step params
      async.end_stage
    else
      queue = Actor[:"queue_#{@uuid}"]
      statements = Actor[:"statements_#{@uuid}"]
      Timings::Pitch.instance(@uuid).cancel
      Timings::FirstPitch.instance(@uuid).cancel
      Timings::VotingQuorum.instance(@uuid).cancel
      statements.voting.calc_votes if statements.voting
      statements.update_visible
      # statements.voting.vote_results! if statements.voting
      # statements.active.each_with_index{|s, i| s.position = i + 1 }
      state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status)
      state.step_status = state.next_enum(State::STEP_STATUSES, state.step_status) unless state.step_status == :end
      Timings::Results.instance(@uuid).start
      queue.next!
      msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: 0, delta: 0}, timer: Timings.instance(@uuid).next_stamp}
      async.publish_msg msg
      players.async.push_end_step params
    end
  end

  def voting_quorum_timeout params = {}
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    queue = Actor[:"queue_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    #calc rank results

    Timings::VotingQuorum.instance(@uuid).cancel
    end_step(status: statements.voting.conclusion)
  end

  def voting_tail_timeout params = {}
  end

  def end_stage params = {}
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    # queue = Actor[:"queue_#{@uuid}"]
    # statements = Actor[:"statements_#{@uuid}"]
    state.stage = state.next_enum(State::STAGES, state.stage)
    Timings::Terminate.instance(@uuid).cancel if state.stage == :tr
    if %w(sw wo ot tr).include? state.stage.to_s
      Timings::BetweenStages.instance(@uuid).start
      msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Timings.instance(@uuid).next_stamp}
      async.publish_msg msg
      players.async.push_end_stage
    elsif %w(rs rw ro rt).include? state.stage.to_s
      msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Time.now.to_i + 1}
      async.publish_msg msg
      players.async.push_end_stage
      async.start_stage
    elsif state.stage == :end
      async.end_game
    end
  end

  def end_game params = {}
    info 'TODO end game'
  end

  def results_timeout params = {}
    state = Actor[:"state_#{@uuid}"]
    statements = Actor[:"statements_#{@uuid}"]
    Timings::Results.instance(@uuid).cancel
    if statements.check_triple_decline
      async.end_stage
    else
      if state.step < state.total_steps
        state.step += 1
        async.start_step
      else
        async.end_stage
      end
    end
  end

  def between_stages_timeout params = {}
    state = Actor[:"state_#{@uuid}"]
    players = Actor[:"players_#{@uuid}"]
    state.stage = state.next_enum(State::STAGES, state.stage)
    state.step = 1
    state.step_status = state.first_enum(State::STEP_STATUSES)

    # check for bugs
    async.start_stage
  end


  def push_event event, params = {}
    publish_msg({type: 'event', subtype: event})
  end

  def push_state params = {}
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    # alarms = Actor[:"alarms_#{@uuid}"]
    msg = params.merge status: state.state, stage: state.stage, timeout_at: Timings::Start.instance(@uuid).at + 1500, started_at: Timings::Start.instance(@uuid).at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    # msg = params.merge status: state.state, stage: state.stage, timeout_at: alarm.next_time, started_at: alarm.start_at, players: players.players.map(&:uuid), step: {total: total_steps, current: step, status: step_status}
    publish_msg msg
  end

  def stage_timeout
    info 'TODO stage timeout'
    async.end_stage
  end

  def terminate_timeout
    info 'terminate_timeout'
    state = int_state
    players = Actor[:"players_#{@uuid}"]
    state.state = :terminated
    publish_msg({type: 'event', subtype: 'terminated'})
    players.async.push_terminated
    async.stop_timers
    async.end_game
  end

  def stop_timers
    timings = Timings.instance(@uuid)
    timings.async.stop_timers
  end

  def publish_msg hash
    state = int_state
    info "publish game #{hash.inspect}"
    # fan = state.game[:fan]
    # fan.publish hash.to_json, routing_key: "game.#{@uuid}"
  end

  def finalizer
    # Center.current.delete(:"alarms_#{@uuid}")
    # Center.current.delete(:"game_#{@uuid}")
    # @alarms.terminate
    # Celluloid::Actor[:channel].terminate
    # Celluloid::Actor[:timers].terminate
  end
end
