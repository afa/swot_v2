class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid

  def initialize params = {}
    if params[:uuid]
      store = Store::Player.find()
    else
      @uuid = UUID.new.generate
    info "player #{params.inspect} started"
    store = Store::Player.create(params.merge(game_uuid: @game_uuid))
    end
    info store.inspect
  end

  def run
  end

  def finalizer
    info "stopping pl #{@uuid}"
  end

end
