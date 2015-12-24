class Player
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  finalizer :finalizer

  attr_accessor :name, :email, :channel, :game_uuid, :uuid

  def initialize params = {}
    if params[:uuid]
    else
    info "player #{params.inspect} started"
    Store::Player.create(params.merge(game_uuid: @uuid))
    end
  end

  def run
  end

  def finalizer
    info 
  end

end
