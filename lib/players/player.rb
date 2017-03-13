require 'score'
class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_reader :name, :email, :channel, :game_uuid, :uuid, :redis, :score, :online, :was_online
  attr_reader :scores
  attr_accessor :order

  def self.build(params = {})
    id = UUID.new.generate
    store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state],
                                 mongo_id: params[:mongo_id], uuid: id, game_uuid: params[:game_uuid],
                                 order: params[:order])
    store
  end

  def initialize(params = {})
    @online = false
    @scores = ::Score.new(self)
    @was_online = false
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      p store
      warn "player #{params.inspect} invalid" unless store
      uuid = store.uuid
      @game_uuid = store.game_uuid
      @name = store.name
      @email = store.email
      @score = store.score
    end
    queue = Actor[:"queue_#{game_uuid}"]
    queue.add uuid
    Center.current.async.to_supervise as: "player_logger_#{uuid}", type: PlayerLogger, args: [{ player_uuid: uuid }]
    info "q first #{queue.first}"
    info store.inspect
    subscribe :send_score, :send_players_score
  end

  def guid?(guid)
    game_uuid == guid
  end

  def current_stamp
    Time.now.to_f.round(3)
  end

  # def run
  # end

  def send_players_score(_topic, guid)
    return unless guid?(guid)
    players = Actor[:"players_#{game_uuid}"]
    dat = players.players.sort { |a, b| a.uuid == b.uuid ? 0 : a.uuid == uuid ? -1 : a.uuid <=> b.uuid }
                 .map { |pl| { pitcher: pl.scores.pitcher_rank, catcher: pl.scores.catcher_score } }
    msg = {
      type: 'event',
      subtype: 'ranks',
      value: dat
    }
    publish_msg msg
  end

  def pitch(params = {})
    queue = Actor[:"queue_#{game_uuid}"]
    return unless queue.pitcher_id == uuid
    Timings::Pitch.instance(game_uuid).cancel
    Timings::FirstPitch.instance(game_uuid).cancel
    game = Actor[:"game_#{game_uuid}"]
    game.pitch(params) # TODO: params for game on pitch done (move code to game.pitch)
  end

  def pass(_params = {})
    info 'start player.pass'
    queue = Actor[:"queue_#{game_uuid}"]
    return unless queue.pitcher_id == uuid
    game = Actor[:"game_#{game_uuid}"]
    Timings::Pitch.instance(game_uuid).cancel
    Timings::FirstPitch.instance(game_uuid).cancel
    game.async.pass
  end

  def vote(params = {})
    val = params[:value]
    game = Actor[:"game_#{game_uuid}"]
    send_vote(value: val)
    game.async.vote(result: val, player: uuid)
    # TODO: params for game on pitch done (move code to game.pitch)
  end

  def ranging(params = {})
    game = Actor[:"game_#{game_uuid}"]
    state = Actor[:"state_#{game_uuid}"]
    send_ranging(value: params[:value], index: params[:index])
    game.async.ranging(value: params[:value], player: uuid, index: params[:index], stage: state.stage)
  end

  def online!
    @online = true
    @was_online = true
    info "#{uuid} online"
    state = Actor[:"state_#{game_uuid}"]
    players = Actor[:"players_#{game_uuid}"]
    players.check_min_players
    async.send_ready reply_to: 'connect' if state.state.to_s == 'waiting'
    async.send_state reply_to: 'connect' if state.state.to_s == 'started'
    async.send_terminated if state.state.to_s == 'terminated'
    async.send_result reply_to: 'connect' unless %w(waiting started).include?(state.state.to_s)
    info 'online'
    publish :player_online, game_uuid, uuid: uuid
  end

  def offline!
    @online = false
    players = Actor[:"players_#{game_uuid}"]
    players.check_min_players
    info "#{uuid} offline"
    publish :player_offline, game_uuid, uuid: uuid
  end

  def publish_msg(msg)
    if online
      ch = Actor[:"chnl_#{uuid}"]
      if ch && ch.alive?
        info 'chnl ok'
        ch.publish_msg msg.merge(time: current_stamp, rel: SWOT_REL, version: SWOT_VERSION).to_json
      else
        info 'chnl down'
        offline!
      end
    else
      info "player #{uuid} offline"
    end
  end

  def send_result(params = {})
    intervals = params.fetch(:intervals, []).map(&:to_sym)
    msg = {
      type: 'event',
      subtype: 'result',
      timeout_at: Timings.instance(game_uuid).stamps(intervals),
      time: current_stamp
    }
    publish_msg msg
  end

  def send_game_results(_params = {})
    statements = Actor[:"statements_#{game_uuid}"]
    players = Actor[:"players_#{game_uuid}"]
    stats = %w(s w o t).map(&:to_sym).inject({}) do |res, sym|
      res[sym] = { statements: [] }
      # TODO: check contrib
      res[sym][:statements] += statements.visible_for_buf(statements.rebuild_visible_for(sym))
                                         .map do |stat|
        { body: stat.value, contribution: '%d%' % (100.0 * stat.contribution_for(uuid)) }
      end
      res
    end
    pls = players.players.sort do |a, b|
      if a.uuid == b.uuid
        0
      elsif a.uuid == uuid
        -1
      else
        a.uuid <=> b.uuid
      end
    end
    cur = pls.shift
    ps = [{ cur.name => { pitcher_score: ('%.03f' % cur.scores.pitcher_score),
                          catcher_score: ('%.03f' % cur.scores.catcher_score) } }] +
         pls.map { |pl| { pl.uglify_name(:s) => { pitcher_score: ('%.03f' % pl.scores.pitcher_score),
                                                  catcher_score: ('%.03f' % pl.scores.catcher_score) } } }
    msg = { type: 'results', value: { data: stats, players: ps } }
    publish_msg msg
  end

  def send_ready(_params = {})
    state = Actor[:"state_#{game_uuid}"]
    queue = Actor[:"queue_#{game_uuid}"]
    p queue
    pit = queue.pitcher.uuid == uuid
    msg = { type: 'event', subtype: 'ready', name: name, start_at: Timings::Start.instance(game_uuid).at,
            pitcher: pit, timeout_at: Timings.instance(game_uuid).stamps(%w(start).map(&:to_sym)),
            version: SWOT_VERSION, time: current_stamp, max_steps: state.total_steps }
    publish_msg msg
  end

  # def send_event ev, params = {}
  #   state = Actor[:"state_#{@game_uuid}"]
  #   msg = {
  #     type: 'event',
  #     subtype: ev, time: current_stamp, time: current_stamp,
  #     timeout_at: Timings.instance(@game_uuid).next_stamp
  #   }.merge params
  #   publish_msg msg
  # end

  def send_pitch(params = {})
    state = Actor[:"state_#{game_uuid}"]
    queue = Actor[:"queue_#{game_uuid}"]
    msg = { type: 'event', subtype: 'pitched', value: params[:value], to_replace: (params[:to_replace] || []),
            author: queue.pitcher.uglify_name(state.stage),
            timeout_at: Timings.instance(game_uuid).stamps(%w(stage voting_quorum voting_tail).map(&:to_sym)),
            time: current_stamp, step: { status: state.step_status } }
    publish_msg msg
  end

  def send_pass
    msg = { type: 'event', subtype: 'passed', time: current_stamp }
    publish_msg msg
  end

  def send_vote(params = {})
    msg = { type: 'event', subtype: 'voted',
            timeout_at: Timings.instance(game_uuid).stamps(%w(voting_quorum voting_tail stage).map(&:to_sym)),
            time: current_stamp }.merge(params)
    publish_msg msg
  end

  def send_quorum
    msg = { type: 'event', subtype: 'quorum',
            timeout_at: Timings.instance(game_uuid).stamps(%w(voting_quorum voting_tail stage).map(&:to_sym)),
            continue: true, time: current_stamp }
    publish_msg msg
  end

  def send_ranging(params = {})
    msg = { type: 'event', subtype: 'ranging', timeout_at: Timings.instance(game_uuid).stamps([:ranging]),
            time: current_stamp }.merge(params)
    publish_msg msg
  end

  def send_messages(_params = {})
    stage = Actor[:"state_#{game_uuid}"].stage
    stage_swot = State::STAGES.fetch(stage, swot: :end)[:swot]
    statements = Actor[:"statements_#{game_uuid}"]
    if %w(rs rw ro rt).include? stage.to_s
      stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot)).map { |stat| stat.as_json(uuid) }
    elsif %w(s w o t sw wo ot tr).include?(stage.to_s)
      stmnts = statements.active_js(uuid)
    else
      stmnts = []
    end
    msg = { type: 'event', subtype: 'statements', value: stmnts }
    publish_msg msg
  end

  # def send_players_score(_topic, guid)
  #   return unless game_uuid == guid
  #   players = Actor[:"players_#{@game_uuid}"]
  #   dat = players.players.sort{|a, b| a.uuid == b.uuid ? 0 : a.uuid == uuid ? -1 : a.uuid <=> b.uuid }.map{|p| {pitcher: p.pitcher_rank, catcher: p.catcher_score} }
  #   msg = {
  #     type: 'event',
  #     subtype: 'ranks',
  #     value: dat
  #   }
  #   publish_msg msg
  # end

  def send_start_step
    state = Actor[:"state_#{game_uuid}"]
    queue = Actor[:"queue_#{game_uuid}"]
    # info "::::::ids #{ queue.ids.index(uuid)}"
    msg = { type: 'event', subtype: 'start_step', turn_in: queue.index(uuid),
            pitcher_name: queue.pitcher.uglify_name(state.stage),
            timeout_at: Timings.instance(game_uuid).stamps(%w(ranging stage first_pitch pitch).map(&:to_sym)),
            step: { current: state.step, total: state.total_steps, status: state.step_status }, time: current_stamp }
    publish_msg msg
  end

  def send_end_step(_params = {})
    queue = Actor[:"queue_#{game_uuid}"]
    statements = Actor[:"statements_#{game_uuid}"]
    stat = statements.last_stat
    if stat
      per = 100 * stat.result.to_f
      per = 100 - per unless stat.status == 'accepted'
      per = stat.status != 'accepted' && stat.unquorumed ? 'no_quorum' : per.round(1)
      rnk = if stat.author != uuid
              { score: scores.catcher_score, delta: '%+.1f' % scores.delta }
            else 
              { score: scores.pitcher_rank }
            end
      msg = { type: 'event', subtype: 'end_step',
              result: { status: (stat.unquorumed ? 'no_quorum' : stat.status), players_voted: per }.merge(rnk),
              timeout_at: Timings.instance(game_uuid).stamps(%w(stage results between_stages).map(&:to_sym)),
              time: current_stamp }
    else
      rnk = if queue.prev_pitcher == uuid
              { rank: scores.pitcher_rank }
            else
              { score: scores.catcher_score, delta: '%+.1f' % scores.delta }
            end
      msg = { type: 'event', subtype: 'end_step', result: { status: params[:status] }.merge(rnk),
              timeout_at: Timings.instance(game_uuid).stamps(%w(stage results between_stages).map(&:to_sym)),
              time: current_stamp }
    end
    publish_msg msg
  end

  def send_start_stage
    queue = Actor[:"queue_#{game_uuid}"]
    state = Actor[:"state_#{game_uuid}"]
    msg = { type: 'event', subtype: 'start_stage', value: state.stage, turn_in: (queue.index(uuid) || 3) }
    publish_msg msg
  end

  def send_end_stage
    state = Actor[:"state_#{game_uuid}"]
    queue = Actor[:"queue_#{game_uuid}"]
    info "sending end stage to pl #{uuid}"

    msg = { type: 'event',
            subtype: 'end_stage',
            value: state.stage,
            pitcher: %w(s w o t sw wo ot).include?(state.stage.to_s) && queue.pitcher == uuid,
            turn_in: (queue.index(uuid) || 3),
            player: { turn_in: (queue.index(uuid) || 3) },
            time: current_stamp,
            timeout_at: Timings.instance(game_uuid).stamps([:between_stages]) }
    publish_msg msg
  end

  def copy_half
    scores.copy_half
  end

  def copy_before
    scores.copy_before
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
    statements = Actor[:"statements_#{game_uuid}"]
    queue = Actor[:"queue_#{game_uuid}"]
    stage = Actor[:"state_#{game_uuid}"].stage
    pitcher = queue.pitcher.uglify_name(stage)
    conclusion = { author: pitcher }
    if statements.voting
      vot = statements.voting
      per = 100 * vot.result.to_f
      per = 100 - per unless vot.status == 'accepted'
      per = per.round(1)
      conclusion.merge!(
        value: vot.value,
        author: Actor[:"player_#{vot.author}"].uglify_name(stage),
        to_replace: vot.replaces.map { |repl| statements.find(repl) }.compact.map(&:value),
        status: vot.status,
        player_score: 0.0, # TODO: fix scores
        players_voted: per
      )
    end
    conclusion
  end

  def gen_state(_params = {})
    queue = Actor[:"queue_#{game_uuid}"]
    state = Actor[:"state_#{game_uuid}"]
    stage_swot = State::STAGES.fetch(state.stage, swot: :end)[:swot]
    statements = Actor[:"statements_#{game_uuid}"]
    stmnts = if %w(rs rw ro rt).include? state.stage.to_s
               statements.visible_for_buf(statements.rebuild_visible_for(stage_swot)).map { |stat| stat.as_json(uuid) }
             elsif %w(s w o t sw wo ot tr).include?(state.stage.to_s)
               statements.active_js(uuid)
             else
               []
             end
    # info "current all statements #{statements.mapped_current}"
    # info "current statements #{statements.active_js}"
    {
      type: 'status',
      version: SWOT_VERSION,
      state: state.state,
      name: name,
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
          turn_in: (queue.index(uuid) || 3)
        },

        started_at: Timings::Start.instance(game_uuid).at,
        timeout_at: Timings.instance(game_uuid).stamps(%w(stage pitch first_pitch voting_quorum voting_tail ranging between_stages results start).map(&:to_sym))
      }
    }
  end

  def send_state(_params = {})
    info "send_state #{uuid}"
    publish_msg gen_state(params)
  end

  # conclusion = [accepted, declined, pass, disconnected]
  # !!!! move to score
  def pitcher_update(conclusion)
    state = Celluloid::Actor[:"state_#{game_uuid}"]
    cfg = state.setting
    mult = cfg[:"pitcher_rank_multiplier_#{conclusion}".to_sym]
    min = cfg[:pitcher_minimum_rank]
    raise "pitcher_rank_multiplier_#{conclusion} not in Settings" unless mult && min
    temp = scores.pitcher_rank * mult
    scores.pitcher_rank = [temp, min].max
  end

  # !!!! move to score
  def catcher_apply_delta(delta)
    scores.catcher_score += delta
    scores.delta = delta
  end

  def finalizer; end
end
