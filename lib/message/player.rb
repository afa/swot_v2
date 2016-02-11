module Message
  module Player
    def subclasses
      cs = constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Class } - [Message::Base, Message::Player::Base]
      p cs
      cs
    end

    module_function :subclasses
  end
end
require 'message/player/base'
require 'message/player/pitch'
# require 'message/player/vote'
# require 'message/player/importate'
require 'message/player/pass'
