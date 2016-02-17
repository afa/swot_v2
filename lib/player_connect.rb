class PlayerConnect
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  def self.create sock, ch
    uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    Celluloid::Internals::Logger.info "WebSocket add for #{uuid}"
    Center.current.to_supervise as: :"chnl_#{uuid}", type: PlayerConnect, args: [sock, ch]
  end

  def initialize sock, ch
    @ch = ch
    @sock = sock
    @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    on
    info "websocket for #{@uuid} ready"
    async.run if @ok
  end

  def publish msg
    if @ok
    @sock.write msg
    p msg
    end
  end

  def run
    begin
      msg = @sock.read
      p 'receive', @uuid, msg
    rescue EOFError => e
      off
    rescue IOError => e
      off
    rescue Exception => e
      p e.class, e.message
      raise
    end
    if @ok
    parse_msg @ch, msg
    async.run
    end
  end

  def on
    a = Actor[:"player_#{@uuid}"]
    if a && a.alive?
      a.online!
    end
    @ok = true
  end

  def off
      @ok = false
      a = Actor[:"player_#{@uuid}"]
      if a && a.alive?
        a.offline!
        Center.current.delete_supervision :"chnl_#{@uuid}"
      end
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



