require "game"
module Message
  module Player
    class Ranging < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        return nil unless hsh[:type] == 'ranging'
        return nil unless ch =~ /\A\/player\//
        # Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
        new ch, hsh
      end

      def initialize ch, hash = {}
        info "init ranging"
        @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
        super
      end

      def process
        info "process ranging"
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        pl.ranging(@data)
      end
    end
  end
end

