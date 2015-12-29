module Message
  module Game
  def subclasses
    cs = constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Class } - [Message::Base]
  end

  module_function :subclasses
  end
end
require 'message/game/start'
require 'message/game/timeout'
# require 'message/game/cancel'
# require 'message/game/terminate'
# require 'message/game/status'
# require 'message/game/stop'
