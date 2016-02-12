require "game"
module Message
  module Player
    class Vote < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        p 'try load vote', hsh
        return nil unless hsh[:type] == 'vote'
        p 'try load vote', ch
        return nil unless ch =~ /\Aplayer\./
        # Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
        new ch, hsh
        # super.tap{|x| p x }
      end

      def initialize ch, hash = {}
        info "init vote"
        @uuid = (/\Aplayer\.(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
        super
      end

      def process
        info "process vote"
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        pl.vote(@data)
      end
    end
  end
end


