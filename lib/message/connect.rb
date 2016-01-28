require "game"
module Message
  class Connect < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      Celluloid::Internals::Logger.info "connect #{ch.inspect} #{hsh.inspect}"
      return nil unless hsh[:type] == 'connect'
      # return nil unless ch == Control::CONTROL_CHANNEL
      super
    end

    def initialize ch, hash = {}
      info "init connect"
      @channel = ch
      super
      # @name = hash[:name] if hash[:name]
      # @players = hash[:players] if hash[:players] && hash[:players].is_a?(Array)
      # @start = hash[:start]
    end

    def process
      info "process connect"
      super
      m = /\/faye\/(player|game)\/(.+)/.match(@channel)
      if m
        case m[1]
        when 'game'
          gm = Celluloid::Actor[:"game_#{m[2]}"]
          gm.async.online! if gm
        when 'player'
          pl = Celluloid::Actor[:"player_#{m[2]}"]
          pl.async.online! if pl
        end
      end
      # ::Game.create(name: @name, players: @players, start: @start)
    end
  end
end

