require "game"
module Message
  class Create < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      return nil unless hsh[:type] == 'create'
      return nil unless ch == '/swot/control'
      # return nil unless ch == Control::CONTROL_CHANNEL
      Celluloid::Internals::Logger.info "create #{ch.inspect} #{hsh.inspect}"
      super
    end

    def initialize ch, hash = {}
      info "init create"
      super
      @name = hash[:name] if hash[:name]
      @players = hash[:players] if hash[:players] && hash[:players].is_a?(Array)
      @start = hash[:start]
      @set = hash[:settings]
    end

    def process
      info "process create"
      super
      ::Game.create(name: @name, players: @players, start: @start, reply: 'create', server_setup: Center.current.server_config.dup, settings: @set)
    end
  end
end
