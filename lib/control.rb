class Control
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::IO
  CONTROL_CHANNEL = '/swot/control'
  finalizer :finalizer

  attr_accessor :control_channel
  def initialize params = {}
    info "starting control"
    @redis = ::Redis.new(driver: :celluloid)
    @channel_name = params[:channel] || CONTROL_CHANNEL
    async.run
    info "start control"
  end

  def run
    self.control_channel = @redis.subscribe(@channel_name) do |on|
      on.message do |ch, msg|
        info "#{ch.inspect} :: #{msg.inspect}"
        sel = begin
                MultiJson.load(msg)
              rescue Exception => e
                {error: e.message}
              end
        info sel.inspect
        klass = ::Message.parse(sel)
        info klass.new(sel).process if klass
      end
      on.subscribe do |ch, subs|
        info "sub #{ch.inspect} -- #{subs.inspect}"
      end
      on.unsubscribe do
        info 'un'
      end
    end
  end
  def finalizer
    info "stop control"
    # self.control_channel.publish "done"
    @redis.unsubscribe '/swot/control'
  end
end
