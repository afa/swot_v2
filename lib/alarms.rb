class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :redis
  # disconnect_timeout
  %w(start stage voting_quorum voting_tail results between_stages first_pitching pitching ranging terminate).each do |sym|
    attr_accessor :"#{sym}_at"
    attr_accessor :"#{sym}"
    p 'def meth', sym
    define_method("set_#{sym}") do |tm|
      info "process #{sym}"
      if get_instance_variable sym
        get_instance_variable(sym).cancel
      end
      if tm
        set_instance_variable :"#{sym}_at", tm.to_i
        set_instance_variable sym, group.now_and_after(tm.to_i - Time.now.to_i) do
          info "fire #{sym}"
          send :"send_#{sym}"
          info "#{sym} fired"
        end
        info 'started start timer ' + (start.fires_in).to_s + ' ' + start.inspect
      end
    end

  end

  def send_start
    @redis.publish "/game/#{game_id}", {type: 'start'}
  end
  


  def initialize params = {}
    info 'setup timers'
    @redis = ::Redis.new
    self.game_id = params[:game_uuid]
    self.group = Timers::Group.new
    p 'time', params
    async.set_start params[:start] if params[:start]
    async.run
    # async.add_one
  end

  def set_start tm

  end

  def run
    # info 'timers started'
    group.wait
    async.run
  end

  def finalizer
    info 'stopping timers'
    group.cancel
    # group.terminate
  end
end
