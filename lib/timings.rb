class Timings
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  attr_reader :stage, :voting_quorum, :voting_tail, :results, :between_stages, :first_pitching, :pitching, :ranging, :terminate
  DEFAULTS = {
    start_timeout: 0,
    stage_timeout: 1500,
    # voting_quorum_timeout: 15,
    voting_quorum_timeout: 60,
    voting_tail_timeout: 15,
    results_timeout: 5,
    between_stages_timeout: 10,
    max_steps: 10,
    # first_pitching_timeout: 15,
    first_pitching_timeout: 120,
    # pitching_timeout: 15,
    pitching_timeout: 20,
    ranging_timeout: 30,
    # disconnect_timeout:
    terminate_timeout: 10
  }

  NAMES = {
    start: Timings::Start,
    stage: Timings::Stage,
    first_pitch: Timings::FirstPitch,
    pitch: Timings::Pitch,
    voting_quorum: Timings::VotingQuorum,
    voting_tail: Timings::VotingTail,
    results: Timings::Results,
    between_stages: Timings::BetweenStages,
    ranging: Timings::Ranging,
    terminate: Timings::Terminate
  }
  def self.subtimers
    constants(false).map{|s| const_get(s) }.select{|c| c.is_a?(Class) } - [Timings::Base]
  end

  def initialize params = {}
    @guid = params.delete(:game_uuid)
    list = self.class.subtimers
    list.map do |cl|
      Center.current.to_supervise as: :"timer_#{cl.reg_name}_#{@guid}", type: cl, args: [{game_uuid: @guid}.merge(DEFAULTS).merge(params)]
    end
  end

  def cleanup
    list = self.class.subtimers
    list.map do |cl|
      Center.current.async.delete_supervision :"timer_#{cl.reg_name}_#{@guid}"
    end
  end

  def pause
  end

  def resume
  end

  def cancel list = []
    list.map{|it| it.instance(@guid) }.each(&:cancel)
  end

  def stamps list = []
    list.inject(10000.0) do |r, l|
      t = NAMES[l].instance(@guid)
      t.next_stamp && r > t.next_stamp ? t.next_stamp : r
    end
  end

  def reset list = []
    list.map{|it| it.instance(@guid) }.each(&:reset)
  end

  def terminate
  end

  def self.instance(id)
    Celluloid::Actor[:"timers_#{id}"]
  end

  def next_stamp
    self.class.subtimers.map{|cl| cl.instance(@guid) }.map(&:next_stamp).compact.min
  end

  def stop_timers
    self.class.subtimers.map{|cl| cl.instance(@guid) }.each(&:cancel)
  end

  def next_interval
    self.class.subtimers.map{|cl| cl.instance(@guid) }.map(&:next_time).compact.min
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
require 'timers/terminate'
