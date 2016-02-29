require 'scores'
class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger
  include Scores

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis, :order, :score, :online
  attr :pitcher_rank, :catcher_score, :delta

  def initialize params = {}
    @online = false
    # @redis ||= ::Redis.new(driver: :celluloid)
    @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      unless store
        info "player #{params.inspect} started"
        store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state], uuid: params[:uuid], game_uuid: params[:game_uuid], score: params[:score] || 0.0)
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
    info "pass to end step"
    game.async.end_step({status: 'passed'})
    info "endstepped"
  end

  def vote params = {}
    
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    send_vote(value: params[:value])
    game.vote(result: params[:value], player: @uuid) #TODO params for game on pitch done (move code to game.pitch)
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
    async.publish :player_online, @game_uuid, {uuid: @uuid}
  end

  def offline!
    @online = false
    players = Actor[:"players_#{@game_uuid}"]
    players.check_min_players
    info "#{@uuid} offline"
    async.publish :player_offline, @game_uuid, {uuid: @uuid}
  end

  def publish_msg msg
    if @online
      ch = Actor[:"chnl_#{@uuid}"]
      if ch && ch.alive?
        p 'chnl ok'
        ch.publish_msg msg.merge(time: current_stamp).to_json
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
    msg = {type: 'event', subtype: 'result',  timer: Timings.instance(@game_uuid).next_stamp}
    publish_msg msg
  end

  def send_ready params = {}
    state = Actor[:"state_#{@game_uuid}"]
    # timers = Actor[:"alarms_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'ready', start_at: Timings::Start.instance(@game_uuid).at, pitcher: (players.queue.index(@uuid) == 0),  timer: Timings.instance(@game_uuid).next_stamp, version: SWOT_VERSION}
    publish_msg msg
  end

  def send_event ev, params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {
      type: 'event', subtype: ev,  timer: Timings.instance(@game_uuid).next_stamp
    }.merge params
    p @uuid, state.player_channels.keys
    publish_msg msg
  end

  def send_pitch params = {}
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'pitched', value: params[:value], to_replace: params[:to_replace], author: queue.pitcher.uglify_name(state.stage.to_s), timer: Timings.instance(@game_uuid).next_stamp, step: {status: state.step_status} }
    publish_msg msg
  end

  def send_pass
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'passed', timer: Timings.instance(@game_uuid).next_stamp}
    publish_msg msg
  end

  def send_vote params = {}
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'voted', timer: Timings.instance(@game_uuid).next_stamp}.merge(params)
    publish_msg msg
  end

  def send_start_step
    game = Actor[:"game_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    info "::::::ids #{ queue.ids.index(@uuid)}"
    msg = {type: 'event', subtype: 'start_step', turn_in: queue.ids.index(@uuid), pitcher_name: queue.pitcher.uglify_name(state.stage), timer: Timings.instance(@game_uuid).next_stamp, step: {current: state.step, total: state.total_steps, status: state.step_status}}
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
      msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: stat.author == @uuid ? @pitcher_rank : @catcher_score, delta: stat.author == @uuid ? 0 : @delta, players_voted: per}, timer: Timings.instance(@game_uuid).next_stamp}
    else
      msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: queue.prev_pitcher == @uuid ? @pitcher_rank : @catcher_score, delta: 0.0}, timer: Timings.instance(@game_uuid).next_stamp}
    end
    publish_msg msg
  end

  def send_start_stage
    players = Actor[:"players_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_stage', value: game.stage, turn_in: (players.queue.index(@uuid) || 3)}
    publish_msg msg
  end

  def send_end_stage
    state = Actor[:"state_#{@game_uuid}"]
    info "sending end stage to pl #{@uuid}"
    msg = {type: 'event', subtype: 'end_stage', value: state.stage, timer: Timings.instance(@game_uuid).next_stamp}
    publish_msg msg
  end

  def send_terminated
    publish_msg({type: 'event', subtype: 'terminated'})
    msg = gen_state
    publish_msg msg
  end

  def uglify_name(stage)
    %w(s t).map(&:to_sym).include?(stage) ? "Player #{order}" : name
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
      conclusion.merge!(
        value: vot.value,
        author: Actor[:"player_#{vot.author}"].uglify_name(state.stage),
        to_replace: vot.replaces,
        status: vot.status,
        player_score: 0.0,
        players_voted: per.to_i
        # players_voted: (100.0 * vot.voted_count.to_f / (players.players.size - 1).to_f).to_i
      )
    end
    conclusion
  end

  def gen_state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    state = Actor[:"state_#{@game_uuid}"]
    statements = Actor[:"statements_#{@game_uuid}"]
    
    info "current all statements #{statements.mapped_current}"
    info "current statements #{statements.active_js}"
    msg = {
      type: 'status',
      version: SWOT_VERSION,
      state: state.state,
      game: {
        time: current_stamp,
        step: {
          current: game.step,
          total: game.total_steps,
          status: game.step_status
        },
        current_stage: game.stage, # one of stages
        conclusion: gen_conclusion,
        replaces: [],
        statements: statements.active_js,
        player: {
          turn_in: (players.queue.index(@uuid) || 3)
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
    mult = Store::Setting.defaults["pitcher_rank_multiplier_#{conclusion}".to_sym]
    min = Store::Setting.defaults[:pitcher_minimum_rank]
    raise "pitcher_rank_multiplier_#{conclusion} not in Settings" unless (mult && min)
    temp = @pitcher_rank * mult
    @pitcher_rank = [temp, min].max
  end

  def catcher_apply_delta(delta)
    @catcher_score += delta
    @catcher_delta = delta
  end

  def finalizer
  end

end
