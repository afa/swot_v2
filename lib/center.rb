# require 'alarms'
# require 'channel_actor'
require 'timings'
require 'control'
require 'log'
require 'message'
require 'vote'
require 'players'
require 'store'
require 'state'
require 'statements'
require 'statement'
require 'score'
require 'admin_logger'
require 'player_logger'
require 'player_connect'
require 'admin_connect'
# require 'client_connect'
class Center # < Celluloid::Supervision::Container
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  attr_accessor :config, :players, :times, :server_config
  finalizer :finalizer

  def self.current
    Actor[:center]
  end

  def initialize params = {}
    @server_config = params
    @players = Players.new
    @times = {start_at: params[:start]}.delete_if{|_k, v| v.nil? }
    info params.inspect
    info 'starting centre'
    build_config
    # async.run
    info 'start centre'
    async.add_web
  end

  def run
    # @config.run
  end

  def add_web
    to_supervise type: Web, as: :web, args: []
  end

  def build_config
    @config = Celluloid::Supervision::Configuration.new
    @config.define type: Control, as: :control, args: [{channel: '/swot/control'}]
    # @config.define type: Web, as: :web, args: ['127.0.0.1', 3010]
    @config.deploy
    # @config = Celluloid::Supervision::Configuration.new
    # @config.define type: Control, as: :control, args: [{channel: '/swot/control'}]
    # @config.deploy
  end

  def to_supervise hash
    info 'supervise'
    info hash.reject{|k, v| k == :args }.inspect
    @config.add(hash)
  end

  def delete_supervision name
    info "clean supervision for #{name}"
    @config.delete name
  end

  def supervision_info
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
