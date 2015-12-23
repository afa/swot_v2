require "game"
module Message
  class Create < Base
    include Celluloid::Internals::Logger
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'create'
      return nil unless hsh[:incoming_channel] == Control::CONTROL_CHANNEL
      new(hsh)
    end

    def initialize hash = {}
      super
      @name = hash[:name] if hash[:name]
      @players = hash[:players] if hash[:players] && hash[:players].is_a?(Array)
    end

    def process
      super
      Game.new(name: @name, players: @players)
    end
  end
end
