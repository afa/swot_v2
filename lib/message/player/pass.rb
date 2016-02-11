require "game"
module Message
  module Player
    class Pass < ::Message::Base
      include Celluloid::Internals::Logger
      def self.try_load(ch, hsh)
        p 'try load pass', hsh
        return nil unless hsh[:type] == 'pass'
        p 'try load pass', ch
        return nil unless ch =~ /\Aplayer\./
        # Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
        p 'try super'
        new ch, hsh
        # super.tap{|x| p x }
      end

      def initialize ch, hash = {}
        info "init pass"
        @uuid = (/\Aplayer\.(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        p @uuid
        @data = hash
        super
      end

      def process
        info "process pass"
        super
        pl = Celluloid::Actor[:"player_#{@uuid}"]
        p 'pass to', pl.uuid
        p pl
        pl.pass(@data)
      end
    end
  end
end


