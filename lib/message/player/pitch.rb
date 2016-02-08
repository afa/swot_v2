require "game"
module Message
  module Player
  class Create < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      Celluloid::Internals::Logger.info "pitch #{ch.inspect} #{hsh.inspect}"
      return nil unless hsh[:type] == 'pitch'
        return nil unless ch =~ /\A\/player\//
      super
    end

    def initialize ch, hash = {}
      info "init pitch"
        @uuid = (/\A\/player\/(?<id>[0-9a-fA-F-]+)\z/.match(ch)||{})[:id]
        @data = hash
      super
    end

    def process
      info "process create"
      super
      pl = Celluloid::Actor[@uuid.to_sym]
      pl.pitch(data: @data)
    end
  end
  end
end

