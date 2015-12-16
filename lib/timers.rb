class Timers
  include Celluloid
  attr_accessor :group

  def initialize
    self.group = Timers::Group.new
  end

  def add_one
    group.after(5) { p 'tim' }

  def run
    loop{ group.wait }
  end
end
