class Alarms # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :group, :start

  def initialize params = {}
    info 'setup timers'
    self.group = Timers::Group.new
    async.run
    async.add_one
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
