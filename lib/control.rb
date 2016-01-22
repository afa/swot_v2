require 'march_hare'
class Control
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::IO
  CONTROL_CHANNEL = '/swot/control'
  finalizer :finalizer

  attr_accessor :control_channel
  def initialize params = {}
    info "starting control"
    @conn = MarchHare.connect
    @ch = @conn.create_channel
    @fan = 1111 #!!!!!!!!!TODO
    @fan_game = @ch.topic('game')
    @fan_player = @ch.topic('player')
    @control_queue = @ch.queue('swot.control').bind(@fan)
    # @sub = ::Redis.new(driver: :celluloid)
    # @redis = ::Redis.new(driver: :celluloid)
    # @channel_name = params[:channel] || CONTROL_CHANNEL
    async.run
    info "start control"
  end

  def add_game(id)
  end

  def add_player(id)
  end

  def clear_game(id)
  end

  def clear_player(id)
  end

  def run
    
    # @redis.subscribe(@channel_name, '/game/*', '/player/*') do |on|
    # @sub.psubscribe('/*/*') do |on|
    #   on.pmessage do |pat, ch, msg|
    #     info "#{ch.inspect} :: #{msg.inspect}"
    #     sel = begin
    #             MultiJson.load(msg)
    #           rescue Exception => e
    #             {error: e.message}
    #           end

    #     info sel.inspect
    #     unless sel[:error]
    #       klass = ::Message.parse(ch, sel)
    #       info klass
    #       klass.new(ch, sel).process if klass
    #     end
    #   end
    #   on.psubscribe do |ch, subs|
    #     # self.control_channel = on
    #     info "sub #{ch.inspect} -- #{subs.inspect}"
    #     info on.inspect
    #   end
    #   on.punsubscribe do
    #     info 'un'
    #     async.stop
    #   end
    # end
  end

  def stop
    # @sub.punsubscribe
    async.terminate
  end

  def finalizer
    info 'closing control'
    @conn.close
    info "stop control"
  end
end
