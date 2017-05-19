require 'scores'
# игрок. внутренний класс, привязан к реестру
class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger
  include Scores

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis, :order, :score, :online, :was_online
  attr_accessor :pitcher_score, :pitcher_rank, :catcher_score, :delta
  attr_accessor :pitcher_score_first_half, :catcher_score_first_half
  attr_accessor :pitcher_score_before_ranging, :catcher_score_before_ranging

  def self.build(params = {})
    Store::Player.create(
      name: params[:name],
      email: params[:email],
      state: params[:state],
      mongo_id: params[:mongo_id],
      uuid: UUID.new.generate,
      game_uuid: params[:game_uuid],
      order: params[:order]
    )
  end

  def initialize(params = {})
    @online = false
    @was_online = false
    # @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      warn "player #{params.inspect} invalid" unless store
      @uuid = store.uuid
      @game_uuid = store.game_uuid
      @name = store.name
      @email = store.email
      @score = store.score
      @pitcher_rank = 1.0
      @catcher_score = 0.0
      @delta = 0.0
    end
    queue = Actor[:"queue_#{@game_uuid}"]
    queue.add @uuid
    Center.current.async.to_supervise as: "player_logger_#{@uuid}", type: PlayerLogger, args: [{ player_uuid: @uuid }]

    subscribe :send_score, :send_players_score
  end

  def current_stamp
    Time.now.to_f.round(3)
  end

  def send_players_score(_topic, guid)
    return unless @game_uuid == guid
    players = Actor[:"players_#{@game_uuid}"]
    dat_sort = players.players.sort do |sa, sb|
      id = sa.uuid
      if id == sb.uuid
        0
      elsif id == @uuid
        -1
      else
        id <=> sb.uuid
      end
    end
    dat = dat_sort.map { |pl| { pitcher: pl.pitcher_rank, catcher: pl.catcher_score } }
    msg = {
      type: 'event',
      subtype: 'ranks',
      value: dat
    }
    publish_msg msg
  end

  def pitch(params = {})
    queue = Actor[:"queue_#{@game_uuid}"]
    return unless queue.pitcher_id == @uuid
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    game = Actor[:"game_#{@game_uuid}"]
    game.pitch(params) # TODO: params for game on pitch done (move code to game.pitch)
  end

  def pass(_params = {})
    # info 'start player.pass'
    queue = Actor[:"queue_#{@game_uuid}"]
    return unless queue.pitcher_id == @uuid
    game = Actor[:"game_#{@game_uuid}"]
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    game.async.pass
  end

  def count_pitcher_score(typ)
    # TODO: step_score.count_pitcher_rank, count_pitcher_score(statements)
    state = Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    mult = cfg[:"pitcher_rank_multiplier_#{typ}"].to_f
    rank = pitcher_rank
    rank *= mult
    self.pitcher_rank = [rank, cfg[:pitcher_minimum_rank].to_f].max
    statements = Actor[:"statements_#{@game_uuid}"]
    statements.count_pitchers_score
  end

  def vote(params = {})
    val = params[:value]
    game = Actor[:"game_#{@game_uuid}"]
    send_vote(value: val)
    game.async.vote(result: val, player: @uuid)
    # TODO: params for game on pitch done (move code to game.pitch)
  end

  def ranging(params = {})
    index = params[:index]
    val = params[:val]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    send_ranging(value: val, index: index)
    game.async.ranging(value: val, player: @uuid, index: index, stage: state.stage)
  end

  def online!
    @online = true
    @was_online = true
    info "#{@uuid} online"
    state_obj = Actor[:"state_#{@game_uuid}"]
    state = state_obj.state.to_s
    players = Actor[:"players_#{@game_uuid}"]
    players.check_min_players
    async.send_ready reply_to: 'connect' if state == 'waiting'
    async.send_state reply_to: 'connect' if state == 'started'
    async.send_terminated if state == 'terminated'
    async.send_result reply_to: 'connect' unless %w(waiting started).include?(state)
    publish :player_online, @game_uuid, uuid: @uuid
  end

  def offline!
    @online = false
    players = Actor[:"players_#{@game_uuid}"]
    players.check_min_players
    info "#{@uuid} offline"
    publish :player_offline, @game_uuid, uuid: @uuid
  end

  def publish_msg(msg)
    if @online
      ch = Actor[:"chnl_#{@uuid}"]
      if ch && ch.alive?
        ch.publish_msg msg.merge(time: current_stamp, rel: SWOT_REL, version: SWOT_VERSION).to_json
      else
        offline!
      end
    else
      info "player #{@uuid} offline"
    end
  end

  def send_result(params = {})
    intervals = params.fetch(:intervals, []).map(&:to_sym)
    msg = { type: 'event',
            subtype: 'result',
            timeout_at: Timings.instance(@game_uuid).stamps(intervals),
            time: current_stamp }
    publish_msg msg
  end

  def send_game_results(params = {})
    statements = Actor[:"statements_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    stats = %w(s w o t).map(&:to_sym).inject({}) do |r, sym|
      r[sym] = { statements: [] }
      # TODO: check contrib
      r[sym][:statements] += statements.visible_for_buf(statements.rebuild_visible_for(sym)).map do |s|
        { body: s.value, contribution: format('%d%', (100.0 * s.contribution_for(@uuid))) }
      end
      r
    end
    pls = players.players.sort do |sa, sb|
      id = sa.uuid
      sbid = sb.uuid
      if id == sbid
        0
      elsif id == @uuid
        -1
      else
        id <=> sbid
      end
    end
    cur = pls.shift
    ps = [{
      cur.name => {
        pitcher_score: format('%.03f', cur.pitcher_score),
        catcher_score: format('%.03f', cur.catcher_score)
      }
    }] + pls.map do |pl|
      {
        pl.uglify_name(:s) => {
          pitcher_score: format('%.03f', pl.pitcher_score),
          catcher_score: format('%.03f', pl.catcher_score)
        }
      }
    end
    msg = { type: 'results', value: { data: stats, players: ps } }
    publish_msg msg
  end

  def send_ready(_params = {})
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    pit = queue.pitcher.uuid == @uuid
    msg = {
      type: 'event', subtype: 'ready', name: @name,
      start_at: Timings::Start.instance(@game_uuid).at, pitcher: pit,
      timeout_at: Timings.instance(@game_uuid).stamps(%w(start).map(&:to_sym)),
      version: SWOT_VERSION, time: current_stamp, max_steps: state.total_steps
    }
    publish_msg msg
  end

  def send_pitch(params = {})
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {
      type: 'event', subtype: 'pitched', value: params[:value], to_replace: (params[:to_replace] || []),
      author: queue.pitcher.uglify_name(state.stage),
      timeout_at: Timings.instance(@game_uuid).stamps(%w(stage voting_quorum voting_tail).map(&:to_sym)),
      time: current_stamp, step: { status: state.step_status }
    }
    publish_msg msg
  end

  def send_pass
    msg = { type: 'event', subtype: 'passed', time: current_stamp }
    publish_msg msg
  end

  def send_vote(params = {})
    msg = {
      type: 'event', subtype: 'voted',
      timeout_at: Timings.instance(@game_uuid).stamps(%w(voting_quorum voting_tail stage).map(&:to_sym)),
      time: current_stamp
    }.merge(params)
    publish_msg msg
  end

  def send_quorum
    msg = {
      type: 'event', subtype: 'quorum',
      timeout_at: Timings.instance(@game_uuid).stamps(%w(voting_quorum voting_tail stage).map(&:to_sym)),
      continue: true, time: current_stamp
    }
    publish_msg msg
  end

  def send_ranging(params = {})
    msg = {
      type: 'event', subtype: 'ranging',
      timeout_at: Timings.instance(@game_uuid).stamps([:ranging]),
      time: current_stamp
    }.merge(params)
    publish_msg msg
  end

  def send_messages(_params = {})
    state = Actor[:"state_#{@game_uuid}"]
    stage = state.stage.to_s
    stage_swot = State::STAGES.fetch(state.stage, swot: :end)[:swot]
    statements = Actor[:"statements_#{@game_uuid}"]
    stmnts = if %w(rs rw ro rt).include? stage
               statements.visible_for_buf(statements.rebuild_visible_for(stage_swot)).map { |st| st.as_json(@uuid) }
             elsif %w(s w o t sw wo ot tr).include?(stage)
               statements.active_js(@uuid)
             else
               []
             end
    msg = { type: 'event', subtype: 'statements', value: stmnts }
    publish_msg msg
  end

  def send_start_step
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {
      type: 'event', subtype: 'start_step', turn_in: queue.index(@uuid),
      pitcher_name: queue.pitcher.uglify_name(state.stage),
      timeout_at: Timings.instance(@game_uuid).stamps(%w(ranging stage first_pitch pitch).map(&:to_sym)),
      step: { current: state.step, total: state.total_steps, status: state.step_status }, time: current_stamp
    }
    publish_msg msg
  end

  def send_end_step(params = {})
    queue = Actor[:"queue_#{@game_uuid}"]
    statements = Actor[:"statements_#{@game_uuid}"]
    stat = statements.last_stat
    if stat
      quorum = stat.quorum?
      status = stat.status
      per = 100 * stat.result.to_f
      per = 100 - per unless status == 'accepted'
      per = quorum ? per.round(1) : 'no_quorum'
      rnk = if stat.author == @uuid
              { score: @pitcher_rank }
            else
              { score: @catcher_score, delta: format('%+.1f', @delta) }
            end
      msg = {
        type: 'event', subtype: 'end_step',
        result: {
          status: (quorum ? status : 'no_quorum'),
          players_voted: per
        }.merge(rnk),
        timeout_at: Timings.instance(@game_uuid).stamps(%w(stage results between_stages).map(&:to_sym)),
        time: current_stamp
      }
    else
      rnk = if queue.prev_pitcher == @uuid
              { rank: @pitcher_rank }
            else
              { score: @catcher_score, delta: format('%+.1f', @delta) }
            end
      msg = {
        type: 'event', subtype: 'end_step',
        result: {
          status: params[:status]
        }.merge(rnk),
        timeout_at: Timings.instance(@game_uuid).stamps(%w(stage results between_stages).map(&:to_sym)),
        time: current_stamp
      }
    end
    publish_msg msg
  end

  def send_start_stage
    queue = Actor[:"queue_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    msg = { type: 'event', subtype: 'start_stage', value: state.stage, turn_in: (queue.index(@uuid) || 3) }
    publish_msg msg
  end

  def send_end_stage
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]

    msg = {
      type: 'event', subtype: 'end_stage', value: state.stage,
      pitcher: %w(s w o t sw wo ot).include?(state.stage.to_s) && queue.pitcher == @uuid,
      turn_in: (queue.index(@uuid) || 3), player: { turn_in: (queue.index(@uuid) || 3) },
      time: current_stamp,
      timeout_at: Timings.instance(@game_uuid).stamps([:between_stages])
    }
    publish_msg msg
  end

  def copy_half
    @catcher_score_first_half = @catcher_score
    @pitcher_score_first_half = @pitcher_score
  end

  def copy_before
    @catcher_score_before_ranging = @catcher_score
    @pitcher_score_before_ranging = @pitcher_score
  end

  def send_terminated
    publish_msg(type: 'event', subtype: 'terminated')
    msg = gen_state
    publish_msg msg
  end

  def uglify_name(stage)
    %w(s sw t tr).map(&:to_sym).include?(stage) ? "Player #{order}" : name
  end

  def gen_conclusion
    statements = Actor[:"statements_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    pitcher = queue.pitcher.uglify_name(state.stage)
    conclusion = { author: pitcher }
    if statements.voting
      vot = statements.voting
      per = 100 * vot.result.to_f
      per = 100 - per unless vot.status == 'accepted'
      per = per.round(1)
      conclusion.merge!(
        value: vot.value,
        author: Actor[:"player_#{vot.author}"].uglify_name(state.stage),
        to_replace: vot.replaces.map { |r| statements.find(r) }.compact.map(&:value),
        status: vot.status,
        player_score: 0.0, # TODO: fix scores
        players_voted: per
      )
    end
    conclusion
  end

  def gen_state(_params = {})
    queue = Actor[:"queue_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    stage_swot = State::STAGES.fetch(state.stage, swot: :end)[:swot]
    statements = Actor[:"statements_#{@game_uuid}"]
    if %w(rs rw ro rt).include? state.stage.to_s
      stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot)).map { |s| s.as_json(@uuid) }
    elsif %w(s w o t sw wo ot tr).include?(state.stage.to_s)
      stmnts = statements.active_js(@uuid)
    else
      stmnts = []
    end

    {
      type: 'status',
      version: SWOT_VERSION,
      state: state.state,
      name: @name,
      game: {
        time: current_stamp,
        step: {
          current: state.step,
          total: state.total_steps,
          status: state.step_status
        },
        current_stage: state.stage, # one of stages
        conclusion: gen_conclusion,
        replaces: [],
        statements: stmnts,
        player: {
          turn_in: (queue.index(@uuid) || 3)
        },

        started_at: Timings::Start.instance(@game_uuid).at,
        timeout_at: Timings.instance(@game_uuid).stamps(
          %w(stage pitch first_pitch voting_quorum voting_tail ranging between_stages results start).map(&:to_sym)
        )
      }
    }
  end

  def send_state(params = {})
    publish_msg gen_state(params)
  end

  def catcher_apply_delta(delta)
    @catcher_score += delta
    @delta = delta
  end

  def finalizer
  end
end
