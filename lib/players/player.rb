class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid

  def initialize params = {}
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

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
