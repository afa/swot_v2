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
  end

  def pass params = {}
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
    ch = 
    {type: 'event', subtype: 'pitched'}
  end

  def send_pass
    {type: 'event', subtype: 'passed'}
  end

  def send_vote
    {type: 'event', subtype: 'voted'}
  end

  def send_start_step
    {type: 'event', subtype: 'start_step'}
  end

  def send_end_step
    {type: 'event', subtype: 'end_step'}
  end

  def start_stage
    {type: 'event', subtype: 'start_stage'}
  end

  def end_stage
    {type: 'event', subtype: 'end_stage'}
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
