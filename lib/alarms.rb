class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Redis
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :redis
  # disconnect_timeout
  %w(start stage voting_quorum voting_tail results between_stages first_pitching pitching ranging terminate).each do |sym|
    attr_accessor "#{sym}_at".to_sym
    attr_accessor "#{sym}".to_sym
    define_method("set_#{sym}") do |tm|
      info "process #{sym}"
      if instance_variable_defined?('@' + sym) && instance_variable_get('@' + sym)
        instance_variable_get('@' + sym).cancel
      end
      if tm
        p tm, group
        instance_variable_set "@#{sym}_at", tm.to_i
        instance_variable_set "@#{sym}", group.after(tm.to_i - Time.now.to_i){
          info "fire #{sym}"
          async.send :"send_#{sym}"
          info "#{sym} fired"
        }
        info 'started start timer ' + (start.fires_in).to_s + ' ' + start.inspect
      end
    end

  end

  def send_start
    # redis = ::Redis.new(driver: :celluloid)
    # p 'start pub', redis
    # p 'pub', redis.publish("/game/#{game_id}", {type: 'start'})
    p 'pubed'

  end
  


  def initialize params = {}
    info 'setup timers'
    # @redis = ::Redis.new(driver: :celluloid, timeout: 0)
    self.game_id = params[:game_uuid]
    self.group = Timers::Group.new
    p 'time', params
    async.set_start params[:start] if params[:start]
    async.run
    # async.add_one
  end

  def run
    info 'timers started'
    group.wait
    async.run
  end

  def finalizer
    info 'stopping timers'
    group.cancel
    # group.terminate
  end
end
