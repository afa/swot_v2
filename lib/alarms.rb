class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :start, :start_at, :redis

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
    if self.start
      start.cancel
    end
    self.start_at = tm.to_i
    start = group.now_and_after(tm.to_i - Time.now.to_i) do
      info 'start fire'
      # Redis.publish "/game/#{game_id}", {type: 'start'}
    end
    info 'started start timer ' + (start.fires_in).to_s + start.inspect

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
