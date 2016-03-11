class AdminConnect
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger
  def self.create sock, ch
    uuid = (/\A\/game\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    lv = Celluloid::Actor[:"chnl_#{uuid}"]
    if lv # && lv.alive?
      Center.current.delete_supervision :"gm_chnl_#{uuid}"
    end
    Celluloid::Internals::Logger.info "WebSocket add for game #{uuid}"
    Center.current.to_supervise as: :"gm_chnl_#{uuid}", type: AdminConnect, args: [sock, ch]
  end

  def initialize sock, ch
    @ch = ch
    @sock = sock
    @uuid = (/\A\/game\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
    on
    info "websocket for game #{@uuid} ready"
    if @ok
      async.publish :admin_channel_connected, @uuid
      async.run
    end
  end

  def publish_msg msg
    if @ok
      begin
        @sock.write msg
        p msg
      rescue EOFError => e
        off
        @sock.close
      rescue IOError => e
        off
        # @sock.close
      rescue Errno::ECONNRESET => e
        off
        @sock.close
      rescue Exception => e
        p e.class, e.message
        off
        @sock.close
        raise
      end
    end
  end

  def run
    begin
      msg = @sock.read
      p 'receive game', @uuid, msg
    rescue EOFError => e
      off
      @sock.close
    rescue IOError => e
      off
      # @sock.close
    rescue Errno::ECONNRESET => e
      off
      @sock.close
    rescue Exception => e
      p e.class, e.message
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
    a = Actor[:"game_#{@uuid}"]
    if a && a.alive?
      a.online!
    end
    @ok = true
  end

  def off
      @ok = false
      a = Actor[:"game_#{@uuid}"]
      if a && a.alive?
        a.offline!
        Center.current.delete_supervision :"gm_chnl_#{@uuid}"
      end
  end

  def parse_msg ch, msg
    # info "#{ch.inspect} :: #{msg.inspect}"
    sel = begin
            MultiJson.load(msg)
          rescue Exception => e
            {error: e.message}
          end

    # info sel.inspect
    unless sel[:error]
      klass = ::Message.parse(ch, sel)
      info klass
      klass.new(ch, sel).process if klass
    end
  end
end
