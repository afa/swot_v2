class PlayerConnect
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def self.create(sock, ch)
    uuid = (%r{\A\/player\/(?<id>[0-9a-fA-F-]+)\z}.match(ch) || {})[:id]
    lv = Celluloid::Actor[:"chnl_#{uuid}"]
    Center.current.delete_supervision :"chnl_#{uuid}" if lv # && lv.alive?
    Center.current.to_supervise as: :"chnl_#{uuid}", type: PlayerConnect, args: [sock, ch]
  end

  def initialize(sock, ch)
    @ch = ch
    @sock = sock
    @uuid = (%r{\A\/player\/(?<id>[0-9a-fA-F-]+)\z}.match(ch) || {})[:id]
    on
    info "websocket for #{@uuid} ready"
    async.run if @ok
  end

  def publish_msg(msg)
    return unless @ok
    begin
      @sock.write msg
    rescue EOFError
      off
      @sock.close
    rescue IOError
      off
      # @sock.close
    rescue Errno::ECONNRESET
      off
      @sock.close
    rescue StandardError => e
      p e.class, e.message
      off
      @sock.close
      raise
    end
  end

  def run
    begin
      msg = @sock.read
    rescue EOFError
      off
      @sock.close
    rescue IOError
      off
      # @sock.close
    rescue Errno::ECONNRESET
      off
      @sock.close
    rescue Exception => e
      info "#{e.class.inspect}, #{e.message}"
      off
      @sock.close
      raise
    end
    if @ok
      parse_msg @ch, msg
      async.run
    end
  end

  def on
    a = Actor[:"player_#{@uuid}"]
    a.online! if a && a.alive?
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

  def parse_msg(ch, msg)
    info "#{ch.inspect} :: #{msg.inspect}"
    sel = begin
            MultiJson.load(msg)
          rescue Exception => exc
            { error: exc.message }
          end

    info sel.inspect
    unless sel[:error]
      klass = ::Message.parse(ch, sel)
      info klass
      klass.new(ch, sel).process if klass
    end
  end
end
