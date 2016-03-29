require 'scores'
class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger
  include Scores

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis, :order, :score, :online
  attr_accessor :pitcher_rank, :catcher_score, :delta

  def self.build params = {}
    d = UUID.new.generate
    store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state], mongo_id: params[:mongo_id], uuid: d, game_uuid: params[:game_uuid])


  # attribute :uuid
  # attribute :state
  # attribute :game_uuid
  # attribute :name
  # attribute :email
  # attribute :score, Type::Decimal
  # attribute :rank, Type::Decimal
  # attribute :order, Type::Integer
  end

  def initialize params = {}
    @online = false
    # @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      unless store
        info "player #{params.inspect} started"
      end
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
    Center.current.async.to_supervise as: "player_logger_#{@uuid}", type: PlayerLogger, args: [{player_uuid: @uuid}]
    p queue.ids
    info "q first #{queue.first}"
    
    info store.inspect
  end

  def current_stamp
    Time.now.to_f.round(3)
  end

  # def run
  # end

  def pitch params = {}
    # timers = Actor[:"alarms_#{@game_uuid}"]
    # timers.async.set_out :pitch, nil
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game.pitch(params) #TODO params for game on pitch done (move code to game.pitch)

  end

  def pass params = {}
    info 'start player.pass'
    game = Actor[:"game_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    Timings::Pitch.instance(@game_uuid).cancel
    Timings::FirstPitch.instance(@game_uuid).cancel
    # timers.async.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    game.async.end_step({status: 'passed'})
  end

  def vote params = {}
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    send_vote(value: params[:value])
    game.async.vote(result: params[:value], player: @uuid) #TODO params for game on pitch done (move code to game.pitch)
  end

  def ranging params = {}
    game = Actor[:"game_#{@game_uuid}"]
    send_ranging(value: params[:value], index: params[:index])
    game.async.ranging(value: params[:value], player: @uuid, index: params[:index])
  end

  def online!
    @online = true
    info "#{@uuid} online"
    state = Actor[:"state_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    players.check_min_players
    async.send_ready reply_to: 'connect' if state.state.to_s == 'waiting'
    async.send_state reply_to: 'connect' if state.state.to_s == 'started'
    async.send_terminated if state.state.to_s == 'terminated'
    async.send_result reply_to: 'connect' unless %w(waiting started).include?(state.state.to_s)
    info 'online'
    publish :player_online, @game_uuid, {uuid: @uuid}
  end

  def offline!
    @online = false
    players = Actor[:"players_#{@game_uuid}"]
    players.check_min_players
    info "#{@uuid} offline"
    publish :player_offline, @game_uuid, {uuid: @uuid}
  end

  def publish_msg msg
    if @online
      ch = Actor[:"chnl_#{@uuid}"]
      if ch && ch.alive?
        p 'chnl ok'
        ch.publish_msg msg.merge(time: current_stamp, rel: SWOT_REL, version: SWOT_VERSION).to_json
      else
        p 'chnl down'
        offline!
      end
    else
      info "player #{@uuid} offline"
    end
    info msg.inspect
  end

  def send_result params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'result',  timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}
    publish_msg msg
  end

  def send_ready params = {}
    state = Actor[:"state_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    pit = queue.pitcher.uuid == @uuid
    msg = {type: 'event', subtype: 'ready', start_at: Timings::Start.instance(@game_uuid).at, pitcher: pit,  timeout_at: Timings.instance(@game_uuid).next_stamp, version: SWOT_VERSION, time: current_stamp}
    publish_msg msg
  end

  def send_event ev, params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {
      type: 'event',
      subtype: ev, time: current_stamp, time: current_stamp,
      timeout_at: Timings.instance(@game_uuid).next_stamp
    }.merge params
    p @uuid, state.player_channels.keys
    publish_msg msg
  end

  def send_pitch params = {}
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage), timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp, step: {status: state.step_status} }
    publish_msg msg
  end

  def send_pass
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'passed', timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}
    publish_msg msg
  end

  def send_vote params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'voted', timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}.merge(params)
    publish_msg msg
  end

  def send_quorum
    msg = {type: 'event', subtype: 'quorum', timeout_at: Timings.instance(@game_uuid).next_stamp, continue: true}
    publish_msg msg
  end

  def send_ranging params = {}
    msg = {type: 'event', subtype: 'ranging', timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}.merge(params)
    publish_msg msg
  end

  def send_start_step
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    # info "::::::ids #{ queue.ids.index(@uuid)}"
    msg = {type: 'event', subtype: 'start_step', turn_in: queue.index(@uuid), pitcher_name: queue.pitcher.uglify_name(state.stage), timeout_at: Timings.instance(@game_uuid).next_stamp, step: {current: state.step, total: state.total_steps, status: state.step_status}, time: current_stamp}
    publish_msg msg
  end

  def send_end_step params = {}
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    statements = Actor[:"statements_#{@game_uuid}"]
    stat = statements.last_stat
    p 'send end step voting', stat
    if stat
      per = 100 * stat.result.to_f
      per = 100 - per unless stat.status == 'accepted'
      per = per.round(1)
      if stat.author == @uuid
        rnk = {rank: @pitcher_rank}
      else
        rnk = {score: @catcher_score, delta: @delta}
      end
      msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], players_voted: per}.merge(rnk), timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}
    # p 'endstep result msg pitcherscore', msg, @pitcher_rank
    else
      if queue.prev_pitcher == @uuid
        rnk = {rank: @pitcher_rank}
      else
        rnk = {score: @catcher_score, delta: @delta}
      end
      msg = {type: 'event', subtype: 'end_step', result: {status: params[:status]}.merge(rnk), timeout_at: Timings.instance(@game_uuid).next_stamp, time: current_stamp}
    end
    publish_msg msg
  end

  def send_start_stage
    queue = Actor[:"queue_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_stage', value: state.stage, turn_in: (queue.index(@uuid) || 3)}
    publish_msg msg
  end

  def send_end_stage
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    info "sending end stage to pl #{@uuid}"

    msg = {
          type: 'event',
          subtype: 'end_stage',
          value: state.stage,
          pitcher: %w(s w o t sw wo ot).include?(state.stage.to_s) && queue.pitcher == @uuid,
          turn_in: (queue.index(@uuid) || 3),
          player: {
            turn_in: (queue.index(@uuid) || 3)
          },
          time: current_stamp,
          timeout_at: Timings.instance(@game_uuid).next_stamp
        }
    publish_msg msg
  end

  def send_terminated
    publish_msg({type: 'event', subtype: 'terminated'})
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
    players = Actor[:"players_#{@game_uuid}"]
    pitcher = queue.pitcher.uglify_name(state.stage)
    conclusion = {author: pitcher}
    if statements.voting
      vot = statements.voting
      per = 100 * vot.result.to_f
      per = 100 - per unless vot.status == 'accepted'
      per = per.round(1)
      conclusion.merge!(
        value: vot.value,
        author: Actor[:"player_#{vot.author}"].uglify_name(state.stage),
        to_replace: vot.replaces,
        status: vot.status,
        player_score: 0.0, #TODO fix scores
        players_voted: per
      )
    end
    conclusion
  end

  def gen_state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    stage_swot = State::STAGES.fetch(state.stage, {swot: :end})[:swot]
    statements = Actor[:"statements_#{@game_uuid}"]
    if %w(rs rw ro rt).include? state.stage.to_s
      stmnts = statements.visible_for_buf(statements.rebuild_visible_for(stage_swot)).map{|s| s.as_json(@uuid) }
    elsif %w(s w o t sw wo ot tr).include?(state.stage.to_s)
      stmnts = statements.active_js(@uuid)
    else 
      stmnts = []
    end
    
    # info "current all statements #{statements.mapped_current}"
    # info "current statements #{statements.active_js}"
    msg = {
      type: 'status',
      version: SWOT_VERSION,
      state: state.state,
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
        timeout_at: Timings.instance(@game_uuid).next_stamp
      },
    }
  end

  def send_state params = {}
    info "send_state #{@uuid}"
    publish_msg gen_state(params)
  end

  # conclusion = [accepted, declined, pass, disconnected]
  def pitcher_update(conclusion)
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    mult = cfg[:"pitcher_rank_multiplier_#{conclusion}".to_sym]
    min = cfg[:pitcher_minimum_rank]
    raise "pitcher_rank_multiplier_#{conclusion} not in Settings" unless (mult && min)
    temp = @pitcher_rank * mult
    @pitcher_rank = [temp, min].max
  end

  def catcher_apply_delta(delta)
    p 'catcher_apply_delta', delta, @catcher_score, @delta
    @catcher_score += delta
    @delta = delta
  end

  def finalizer
  end

end
