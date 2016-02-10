require 'alarms'
# require 'channel_actor'
require 'control'
require 'log'
require 'message'
require 'players'
require 'store'
require 'state'
class Center # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  attr_accessor :config, :players, :times
  finalizer :finalizer

  def self.current
    Actor[:center]
  end

  def initialize params = {}
    @players = Players.new
    @times = {start_at: params[:start]}.delete_if{|_k, v| v.nil? }
    info params.inspect
    info 'starting centre'
    build_config
    # async.run
    info 'start centre'
  end

  def run
    # @config.run
  end

  def build_config
    @config = Celluloid::Supervision::Configuration.new
    @config.define type: Control, as: :control, args: [{channel: '/swot/control'}]
    @config.deploy
  end

  def to_supervise hash
    info 'supervise'
    info hash.inspect
    @config.add(hash)
  end

  def delete_supervision name
    @config.delete name
  end

  def stop
    info 'receive stop'
    async.terminate if Actor[:center].alive?
  end


  # Control.supervise as: :control, args: [{channel: '/swot/control'}]

  def finalizer
    info 'finalizing centre'
    @config.shutdown
    # Actor[:control].async.terminate
    info 'finalize centre'
  end
end
