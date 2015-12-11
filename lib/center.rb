require 'timers'
require 'channel_actor'
require 'control'
class Center
  def initialize
    @control = Control.new
  end

  def run
    @control.async.run
    p 'ce-ok'
    sleep 10
    p 'ce'
  end
end
