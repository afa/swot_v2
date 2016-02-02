class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Redis
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :redis
  attr :start, :start_at, :stage, :stage_at
  # disconnect_timeout
  %w(stage voting_quorum voting_tail results between_stages first_pitching pitching ranging terminate).each do |sym|
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
          @start.cancel if @start
          group.cancel unless group.timers.detect{|t| t.fires_in > 0 }
          # @start = nil
          info "fire #{sym}"
          async.send :"send_#{sym}"
          info "#{sym} fired"
        }
        info 'started start timer ' + (start.fires_in).to_s + ' ' + start.inspect
      end
    end

  end

  def next_time
    group.wait_interval
  end

  def initialize params = {}
    info 'setup timers'
    # @redis = ::Redis.new(driver: :celluloid, timeout: 0)
    self.game_id = params[:uuid]
    self.group = Timers::Group.new
    p 'time', params
    set_out :start, params[:start] if params[:start]
    async.run
    # async.add_one
  end

  def set_out what, time
    info "process #{what}"
    instance_variable_get("@#{what}").cancel if instance_variable_defined?("@#{what}") && instance_variable_get("@#{what}")
    if time
      instance_variable_set("@#{what}_at", time.to_i)
      instance_variable_set("@#{what}", group.after(instance_variable_get("@#{what}_at") - Time.now.to_i){
        info "fire #{what}"
        async.send(:"send_#{what}")
        info "#{what} fired"
      })
      info "started #{what} timer #{instance_variable_get("@#{what}")}"
      async.run if next_time.try(:>, 0)
    end
  end
  # def set_start time
  #   info 'process start'
  #   @start.cancel if @start
  #   if time
  #       p time, group
  #       @start_at = time.to_i
  #       @start = group.after(@start_at - Time.now.to_i){
  #         info "fire start"
  #         async.send_start
  #         info "start fired"
  #       }
  #       info 'started start timer ' + (@start.fires_in).to_s
  #   else 
  #     @start_at = nil
  #   end
  #   async.run
  # end

  def send_start
    if @game_id
      gm = Actor[:"game_#{@game_id}"]
      gm.async.start
      info "game #{@game_id} send start"
    end

    # redis = ::Redis.new(driver: :celluloid)
    # p 'start pub', redis
    # p 'pub', redis.publish("/game/#{game_id}", {type: 'start'})
    p 'pubed'

  end
  
  def send_stage
    info 'stage timeout'
  end

  def send_pitch
  end

  def send_vote
  end

  def run
    info "timers run #{group.wait_interval}"
    group.wait
    async.run if group.wait_interval && group.wait_interval > 0
  end

  def finalizer
    info 'stopping timers'
    group.cancel
    # group.terminate
  end
end
