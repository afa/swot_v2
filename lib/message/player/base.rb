module Message
  module Player
    class Base < ::Message::Base
      def self.try_load ch, hash
        super
      end
    end
  end
end
