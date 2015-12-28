module Message
  module Game
    class Start < Base
      include Celluloid::Internals::Logger
      attr_accessor :game_uuid
      def self.try_load(hsh)
        return nil unless hsh[:type] == 'start'
        super
      end

      def initialize hash
        super
        @game_uuid = hash[:uuid]
      end

      def process
        super
        info 'starting game'
        game = Celluloid::Actor[:"game_#{@game_uuid}"]
        if game.alive?
          game.async.start
        end
        info "send start to #{@game_uuid}"
      end
    end

  end
end

