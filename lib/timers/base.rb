class Timings::Base
  attr :guid, :timer, :at, :paused_at, :interval

  def initialize(params = {})
    @guid = params.delete(:game_uuid)
  end

  def self.instance(id)
    Celluloid::Actor[:"timer_#{reg_name}_#{id}"]
  end

  def next_time
    return nil unless @timer
    return nil unless @at
    tm = Time.now.to_i
    return nil if @at <= tm
    @at - tm
  end

  def at
    @at || @old_time
  end

  def next_stamp
    return nil unless @timer
    return nil unless @at
    return nil if @at <= Time.now.to_i
    @at
  end

  def start
    @at = Time.now.to_i + @interval
    if @timer
      @timer.cancel
      @timer.reset
    else
      @timer = after(@interval) { process }
    end
  end

  def set_time(time)
    ctime = Time.now.to_i
    if time.kind_of?(Time)
      @at = time.to_i
      raise if @at < ctime
    elsif time.kind_of?(Numeric)
      if time < ctime
        raise
      end
      @at = time
    end
    @timer.cancel if @timer
    @timer = after(@at - ctime) { process }
  end

  def reset
    return unless @timer
    @timer.reset
  end

  def cancel
    return unless @timer
    @old_time = @at if @at
    @at = nil
    @timer.cancel
  end

  def process
    info "run timeout on #{self.class.reg_name} at #{Time.at(@at)}"
    @timer.cancel
  end
end
