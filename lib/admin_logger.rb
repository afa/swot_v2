class AdminLogger
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize params = {}
    @guid = params[:game_uuid]
    subscribe :player_online, :player_online
    subscribe :player_offline, :player_offline
  end

  def player_online topic, params = {}
    info "----------------------player #{params[:uuid]} (#{topic}) online----------------------------"
  end

  def player_offline topic, params = {}
    info "----------------------player #{params[:uuid]} (#{topic}) offline----------------------------"
  end

end
