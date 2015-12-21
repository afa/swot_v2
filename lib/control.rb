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
    @redis.subscribe(@channel_name) do |on|
      on.message do |ch, msg|
        info "#{ch.inspect} :: #{msg.inspect}"
        sel = begin
                MultiJson.load(msg)
              rescue Exception => e
                {error: e.message}
              end
        info sel.inspect
        unless sel[:error]
          klass = ::Message.parse(sel)
          info klass
          klass.new(sel).process if klass
        end
      end
      on.subscribe do |ch, subs|
        self.control_channel = on
        info "sub #{ch.inspect} -- #{subs.inspect}"
        info on.inspect
      end
      on.unsubscribe do
        info 'un'
      end
    end
  end
  def finalizer
    info "stop control"
    # self.control_channel.publish "done"
    control_channel.unsubscribe
    info 'unsubscribed'
  end
end
