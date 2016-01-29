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


  def state
    msg = {
      type: 'status',
      game: {
      },
      statements: {
        replaces: [],

      },
      current_stage: %w(s sw w wo o ot t tr rs rw ro rt), # one of stages
      step: {
        current: 1,
        total: 60,
        status: %w(pitch vote end)
      },
      started_at: timestamp,
      timeout_at: when timeout
    }
    async.publish msg
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
