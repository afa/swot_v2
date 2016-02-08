class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid, :redis

  def initialize params = {}
    # @redis ||= ::Redis.new(driver: :celluloid)
    @game_uuid = params[:game_uuid]
    if params[:uuid]
      store = Store::Player.find(uuid: params[:uuid]).first
      unless store
        info "player #{params.inspect} started"
        store = Store::Player.create(name: params[:name], email: params[:email], state: params[:state], uuid: params[:uuid], game_uuid: params[:game_uuid])
      end
      @uuid = store.uuid
      @game_uuid = store.game_uuid
      @name = store.name
      @email = store.email
    end
    info store.inspect
  end

  # def run
  # end

  def pitch params = {}
    timers = Actor[:"timers_#{@game_uuid}"]
    timers.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    game = Actor[:"game_#{@game_uuid}"]
    game.pitch #TODO params for game on pitch done
    state = Actor[:"state_#{@game_uuid}"]
    players.async.push_pitch(value: params[:value], to_replace: params[:to_replace], author: uglify_name(state.stage.to_s), timer: Time.now.to_i + state.settings[:vote_timeout])
    timers.set_out :vote, Time.now.to_i + state.settings[:vote_timeout]
    statement = Statement.new(value: params[:value], replaces: params[:to_replace], author: @uuid, stage: state.stage, step: state.step, game_uuid: @game_uuid)
  end

  def pass params = {}
    game = Actor[:"game_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    timers.set_out :pitch, nil
    players = Actor[:"players_#{@game_uuid}"]
    game.end_step
  end

  def vote params = {}
  end

  def online!
    send_state reply_to: 'connect'
    info 'online'
  end

  def offline!
    info 'offline'
  end

  def send_pitch
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'pitched'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_pass
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'passed'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_vote
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'voted'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_start_step
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_step'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def send_end_step
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_step'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def start_stage
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'start_stage'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def end_stage
    state = Actor[:"state_#{@game_uuid}"]
    msg = {type: 'event', subtype: 'end_stage'}
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish msg.to_json, routing_key: "player.#{@uuid}"
  end

  def uglify_name(stage)
    %w(s t).include?(stage) ? "Player #{order}" : name
  end

  def state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    msg = {
      type: 'status',
      state: 'started',
      game: {
        step: {
          current: game.step,
          total: game.total_steps,
          status: game.step_status
        },
        current_stage: game.stage, # one of stages
        conclusion: {},
          replaces: [],
        statements: game.statements,
        player: {
          turn_in: (players.queue.index(@uuid) || 3)
        },

        started_at: timers.start_at.to_i,
        timeout_at: timers.next_time
      },
    }
  end

  def send_state params = {}
    state = Actor[:"state_#{@game_uuid}"]
    ch = state.player_channels[:"player.#{@uuid}"]
    ch[:x].publish state(params).to_json, routing_key: "player.#{@uuid}"
    info state(params).to_json
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
