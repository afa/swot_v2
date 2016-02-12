class Alarms
  include Celluloid
  include Celluloid::IO
  # include Celluloid::Redis
  include Celluloid::Internals::Logger
  finalizer :finalizer
  attr_accessor :game_id, :group, :redis
  attr :start, :start_at, :stage, :stage_at
  attr :pitch, :pitch_at, :first_pitch, :first_pitch_at, :voting_quorum, :voting_quorum_at, :voting_tail, :voting_tail_at
  attr :results, :results_at, :between_stages, :between_stages_at
  # disconnect_timeout
  # %w(stage voting_quorum voting_tail results between_stages first_pitching pitching ranging terminate).each do |sym|

  # end

  def next_time
    p Time.now
    s = group.wait_interval
    p Time.now
    s
  end

  def next_stamp
    return nil unless next_time
    return nil unless next_time > 0
    Time.now.to_i + next_time
  end

  def initialize params = {}
    info 'setup timers'
    # @redis = ::Redis.new(driver: :celluloid, timeout: 0)
    @game_id = params[:uuid]
    self.group = Timers::Group.new
    p 'time', params
    async.set_out :start, params[:start] - Time.now.to_i if params[:start]
    async.run
    # async.add_one
  end

  def set_out what, time
    info "process #{what}"
    # instance_variable_get("@#{what}").cancel if instance_variable_defined?("@#{what}") && instance_variable_get("@#{what}")
    group.cancel
    if time
      if instance_variable_defined?("@#{what}") && instance_variable_get("@#{what}")
        instance_variable_set("@#{what}_at", Time.now + time.to_i)
        instance_variable_get("@#{what}").reset
      else
        instance_variable_set("@#{what}_at", Time.now + time.to_i)
        instance_variable_set("@#{what}", group.after(time.to_i){
          info "fire #{what}"
          async.send(:"send_#{what}")
          info "#{what} fired"
        })
      end
      info "started #{what} timer #{instance_variable_get("@#{what}")}"
    end
    async.run if next_time.try(:>, 0)
  end

  # def send_start
  #   if @game_id
  #     gm = Actor[:"game_#{@game_id}"]
  #     state = Actor[:"state_#{@game_id}"]
  #     gm.async.start
  #     info "game #{@game_id} send start"
  #   end
  # end
  
  # def send_stage
  #   info 'stage timeout'
  #   async.set_out :stage, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.stage_timeout
  #   info 'stage timeout fired'
  # end

  # def send_first_pitch
  #   info 'first pitch send'
  #   async.set_out :first_pitch, nil
  #   send_pitch first: true
  #   info 'first pitch timeout fired'
  # end

  # def send_pitch params = {}
  #   info 'pitch send'
  #   async.set_out :pitch, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.pitch_timeout params
  #   info 'pitch timeout fired'
  # end

  # def send_voting_quorum
  #   info 'voting_quorum send'
  #   async.set_out :voting_quorum, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.voting_quorum_timeout
  #   info 'voting_quorum timeout fired'
  # end

  # def send_voting_tail
  #   info 'voting tail send'
  #   async.set_out :voting_tail, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.voting_tail_timeout
  #   info 'voting_tail timeout fired'
  # end

  # def send_results
  #   info 'results send'
  #   async.set_out :results, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.results_timeout
  #   info 'results timeout fired'
  # end

  # def send_between_stages
  #   async.set_out :between_stages, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.between_stages_timeout
  #   info 'between_stages timeout fired'
  # end

  # def send_between_stages_timeout
  #   set_out :pitch, nil
  #   gm = Actor[:"game_#{@game_id}"]
  #   gm.async.pitch_timeout
  #   info 'stage timeout fired'
  # end

  def run
    info "timers run #{group.wait_interval}"
    group.wait
    async.run if group.wait_interval && group.wait_interval > 0
  end

  def finalizer
    info 'stopping timers'
    group.cancel
    # group.terminate
  end
end
