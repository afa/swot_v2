module Message
  module Game
    class Timeout < Base
      include Celluloid::Internals::Logger
      attr_accessor :game_uuid
      def self.try_load(hsh)
        return nil unless hsh[:type] == 'timeout'
        super
      end

      def initialize hash
        super
        @game_uuid = hash[:uuid]
      end

      def process
        super
        info 'game timeout'
        game = Celluloid::Actor[:"game_#{@game_uuid}"]
        if game.alive?
          game.async.timeout
        end
        info "send timeout to #{@game_uuid}"
      end
    end

  end
end
