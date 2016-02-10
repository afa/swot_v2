module Message
  module Game
    class Start < Base
      include Celluloid::Internals::Logger
      attr_accessor :game_uuid
      def self.try_load(ch, hsh)
        return nil unless ch =~ /\A\/game\//
        return nil unless hsh[:type] == 'start'
        Celluloid::Internals::Logger.info "msg #{ch} #{hsh.inspect}"
        super
      end

      def initialize ch, hash
        @game_uuid = (/\A\/game\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        info "msg start #{@game_uuid}"
        super

      end

      def process
        super
        info 'starting game'
        game = Celluloid::Actor[:"game_#{@game_uuid}"]
        p game.uuid
        if game
          info 'game exist'
          info game.uuid
          info game.alive?.inspect
          if game.alive?
            game.async.start 
            info "game #{game.uuid} found and alive"
          end
        end
        info "send start to #{@game_uuid}"
      end
    end

  end
end

