require 'alarms'
require 'channel_actor'
require 'control'
require 'log'
require 'message'
class Center < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::Internals::Logger
  finalizer :finalizer

  def initialize params = {}
    info params.inspect
    info 'starting centre'
    super
    info 'start centre'
  end

  Control.supervise as: :control, args: [{channel: '/swot/control'}]

  def finalizer
    info 'finalizing centre'
    Actor[:control].async.terminate
    info 'finalize centre'
  end
end
