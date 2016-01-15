require "game"
module Message
  class Create < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      Celluloid::Internals::Logger.info "create #{ch.inspect} #{hsh.inspect}"
      return nil unless hsh[:type] == 'create'
      return nil unless ch == Control::CONTROL_CHANNEL
      Celluloid::Internals::Logger.info "really create"
      super
      # new(hsh)
    end

    def initialize ch, hash = {}
      info "init create"
      super
      @name = hash[:name] if hash[:name]
      @players = hash[:players] if hash[:players] && hash[:players].is_a?(Array)
    end

    def process
      info "process create"
      super
      ::Game.create(name: @name, players: @players)
    end
  end
end
