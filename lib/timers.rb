class Timers
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  attr_reader :stage, :voting_quorum, :voting_tail, :results, :between_stages, :first_pitching, :pitching, :ranging, :terminate
  DEFAULTS = {
      stage_timeout: 1500,
      voting_quorum_timeout: 60,
      voting_tail_timeout: 15,
      results_timeout: 5,
      between_stages_timeout: 10,
      max_steps: 60,
      first_pitching_timeout: 120,
      pitching_timeout: 20,
      ranging_timeout: 30,
      # disconnect_timeout:
      terminate_timeout: 10
  }

  def subtimers
    self.class.constants(false).map{|s| const_get(s) } - [Timers::Base]
  end

  def initialize params = {}
    @guid = params.delete(:game_uuid)
    list = subtimers
    list.map do |cl|
      Center.current.to_supervise as: :"timer_#{cl.reg_name}_#{@guid}", type: cl, args: [{game_uuid: @guid}.merge(DEFAULTS).merge(params)]
    end
  end

  def pause
  end

  def resume
  end

  def cancel
  end

  def reset
  end

  def next_interval
    subtimers.map{|cl| cl.instance(@guid) }.map(&:next_time).compact.min
  end

end

require 'timers/base'
require 'timers/start'
require 'timers/stage'
require 'timers/first_pitch'
require 'timers/pitch'
require 'timers/voting_quorum'
require 'timers/voting_tail'
require 'timers/results'
require 'timers/between_stages'
require 'timers/ranging'
# require 'timers/terminate'
