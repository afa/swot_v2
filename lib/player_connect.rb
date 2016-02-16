class PlayerConnect
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  def self.create sock, ch
    uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    Center.current.to_supervise as: :"chnl_#{uuid}", type: PlayerConnect, args: [sock, ch]
  end

  def initialize sock, ch
    @ch = ch
    @sock = sock
    @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    p 'tttttt'
     p @uuid
     p self
    # sock.on_message{|m| p m }
    # p sock
    # @driver = sock.driver
    # @driver = WebSocket::Driver.server(sock)
    # @driver.on(:message) do |meta|
    #   p 'aaa'
    #   info "meta #{meta.inspect}"
    # end
    # @driver.on(:close){ p 'close' }
    async.run
  end

  def publish msg
    @sock.write msg
    p msg
  end

  def run
    msg = @sock.read
    parse_msg @ch, msg
    async.run
    # p @sock.read
    # p 'aaa1'
    # @driver.start
    # p 'aaa2'
    # @driver.on(:open){|e| d.start }
  end

  def parse_msg ch, msg
    info "#{ch.inspect} :: #{msg.inspect}"
    sel = begin
            MultiJson.load(msg)
          rescue Exception => e
            {error: e.message}
          end

    info sel.inspect
    unless sel[:error]
      klass = ::Message.parse(ch, sel)
      info klass
      klass.new(ch, sel).process if klass
    end
  end
end



