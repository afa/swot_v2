require 'reel'
require 'websocket/driver'
class Web < Reel::Server::HTTP
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize params = {}
    cfg = Center.current.server_config
    host = cfg[:host]
    port = cfg[:port]
    info "server starting on #{host}:#{port}"
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    while request = connection.request
      if request.websocket?
        info "Received a WebSocket connection"

        # We're going to hand off this connection to another actor (TimeClient)
        # However, initially Reel::Connections are "attached" to the
        # Reel::Server::HTTP actor, meaning that the server manages the connection
        # lifecycle (e.g. error handling) for us.
        # 
        # If we want to hand this connection off to another actor, we first
        # need to detach it from the Reel::Server (in this case, Reel::Server::HTTP)
        connection.detach

        route_websocket request.websocket
        return
      else
        route_request connection, request
      end
    end
  end

  def route_request(connection, request)
    # if request.url == "/"
    #   return render_index(connection)
    # end

    info "404 Not Found: #{request.path}"
    connection.respond :not_found, "Not found"
  end

  def route_websocket(socket)
    if socket.url =~ /\/player\//
      PlayerConnect.create(socket, socket.url)
    elsif socket.url == '/swot/control'
      p 'control channel TODO'
      # ClientConnect(socket)
    end
  end
end
