class Alarms < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  attr_accessor :group

  def initialize
    self.group = Alarms::Group.new
    async.run
  end

  def add_one
    group.after(5) { p 'tim' }
  end

  def run
    loop{ group.wait }
  end
end
