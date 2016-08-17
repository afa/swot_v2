require "game"
module Message
  module Player
    class Pass < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        return nil unless hsh[:type] == 'pass'
        return nil unless ch =~ /\A\/player\//
        # Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
        new ch, hsh
        # super.tap{|x| p x }
      end

      def initialize ch, hash = {}
        @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
        super
      end

      def process
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        info "pass to #{pl.uuid}"
        pl.async.pass(@data)
      end
    end
  end
end


