require "game"
module Message
  module Player
    class Pitch < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        p 'try load pitch', hsh
        return nil unless hsh[:type] == 'pitch'
        p 'try load pitch', ch
        return nil unless ch =~ /\Aplayer\./
        # Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
        p 'try super'
        new ch, hsh
        # super.tap{|x| p x }
      end

      def initialize ch, hash = {}
        info "init pitch"
        @uuid = (/\Aplayer\.(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
        super
      end

      def process
        info "process pitch"
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        pl.pitch(@data)
      end
    end
  end
end

