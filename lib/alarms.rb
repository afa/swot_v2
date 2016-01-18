class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :start, :redis

  def initialize params = {}
    info 'setup timers'
    @redis = ::Redis.new
    self.game_id = params[:game_uuid]
    self.group = Timers::Group.new
    set_start params[:start] if params[:start]
    async.run
    # async.add_one
  end

  def set_start tm
    if self.start
      start.cancel
    end
    group.after(tm.to_i - Time.now.to_i){Redis.publish "/game/#{game_id}", {type: 'start'}}
    self.start = tm.to_i
  end

  def add_one
    p 'add_one'
    group.after(5) { p 'tim' }
  end

  def run
    info 'timers started'
    # loop{ group.wait }
  end

  def finalizer
    info 'stopping timers'
    group.cancel
    # group.terminate
  end
end
