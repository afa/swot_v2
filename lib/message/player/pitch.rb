require "game"
module Message
  module Player
    class Pitch < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        return nil unless hsh[:type] == 'pitch'
        return nil unless ch =~ /\A\/player\//
        new ch, hsh
        # super.tap{|x| p x }
      end

      def initialize ch, hash = {}
        @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
        super
      end

      def process
        # info "process pitch"
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        pl.pitch(@data)
      end
    end
  end
end

