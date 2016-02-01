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
        store = Store::Player.create(params)
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
    {type: 'event', subtype: 'pitch'}
  end

  def send_pass
    {type: 'event', subtype: 'pass'}
  end

  def send_vote
    {type: 'event', subtype: 'vote'}
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


  def state params = {}
    game = Actor[:"game_#{@game_uuid}"]
    timers = Actor[:"timers_#{@game_uuid}"]
    msg = {
      type: 'status',
      game: {
        step: {},
        current_stage: %w(s sw w wo o ot t tr rs rw ro rt), # one of stages
        conclusion: {},
          replaces: [],
        statements: game.statements

          ],

        started_at: timers.started_at.to_i,
        timeout_at: timers.next_time
      },
      step: {
        current: 1,
        total: 60,
        status: %w(pitch vote end)
      },
    }
    async.publish msg.merge(params)
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
