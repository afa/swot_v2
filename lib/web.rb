require 'reel'
require 'websocket/driver'
# class Reel::MessageStream
#     def initialize a, b
#       p 'ms'
#     end
# end
class Web < Reel::Server::HTTP
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize(host = "192.168.112.220", port = 3010)
  # def initialize(host = "127.0.0.1", port = 3010)
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
      # socket.on_message{ p 'ffffffffff' }
      # socket.write('aaaaaaaaa')
      PlayerConnect.create(socket, socket.url)
    elsif socket.url == '/swot/control'
      p 'control channel TODO'
      # ClientConnect(socket)
    end
    # d = WebSocket::Driver.server(socket)
    # d.on(:open){|e| d.start; info 'open' }
    # d.on(:message){|e| info "msg #{e.body.to_s}" }
    # info "d  #{d.inspect}"

  end

  def render_index(connection)
    info "200 OK: /"
    connection.respond :ok, <<-HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Reel WebSockets time server example</title>
        <style>
          body {
            font-family: "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif;
            font-weight: 300;
            text-align: center;
          }
          #content {
            width: 800px;
            margin: 0 auto;
            background: #EEEEEE;
            padding: 1em;
          }
        </style>
      </head>
      <script>
        var SocketKlass = "MozWebSocket" in window ? MozWebSocket : WebSocket;
        var ws = new SocketKlass('ws://' + window.location.host + '/timeinfo');
        ws.onmessage = function(msg){
          document.getElementById('current-time').innerHTML = msg.data;
        }
      </script>
      <body>
        <div id="content">
          <h1>Time Server Example</h1>
          <div>The time is now: <span id="current-time">...</span></div>
        </div>
      </body>
      </html>
    HTML
  end
end
