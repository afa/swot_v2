require 'alarms'
require 'channel_actor'
require 'control'
require 'log'
require 'message'
class Center # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::Internals::Logger
  attr_accessor :config
  finalizer :finalizer

  def self.current= obj
    class_variable_set(:@@current, obj)
  end

  def self.current
    class_variable_get :@@current
  end

  def initialize params = {}
    info params.inspect
    info 'starting centre'
    build_config
    # async.run
    self.class.current = self
    info 'start centre'
  end

  def build_config
    @config = Celluloid::Supervision::Configuration.new
    @config.define type: Control, as: :control, args: [{channel: '/swot/control'}]
    @config.deploy
  end

  def to_supervise hash
    info hash
    @config.define hash
  end

  def stop
    terminate
  end


  # Control.supervise as: :control, args: [{channel: '/swot/control'}]

  def finalizer
    info 'finalizing centre'
    @config.shutdown
    # Actor[:control].async.terminate
    info 'finalize centre'
  end
end
