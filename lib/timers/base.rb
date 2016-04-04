class Timings::Base

  attr :guid, :timer, :at, :paused_at, :interval

  def initialize params = {}
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
    # !start
    if @timer
      @timer.cancel
      @at = Time.now.to_i + @interval
      @timer.reset
    else
      @at = Time.now.to_i + @interval
      @timer = after(@interval) { process }
    end
  end

  def set_time time
    #only start
    if time.kind_of?(Time)
      @at = time.to_i
      raise if @at < Time.now.to_i
    elsif time.kind_of?(Numeric)
      if time < Time.now.to_i
        p time, Time.now.to_i
        raise
      end
      @at = time
    end
    @timer.cancel if @timer
    @timer = after(@at - Time.now.to_i) { process }
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
