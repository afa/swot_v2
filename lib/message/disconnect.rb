require "game"
module Message
  class Disconnect < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      return nil unless hsh[:type] == 'disconnect'
      # return nil unless ch == Control::CONTROL_CHANNEL
      Celluloid::Internals::Logger.info "disconnect #{ch.inspect}"
      super
    end

    def initialize ch, hash = {}
      info "init disconnect"
      @channel = ch
      super
      # @name = hash[:name] if hash[:name]
      # @players = hash[:players] if hash[:players] && hash[:players].is_a?(Array)
      # @start = hash[:start]
    end

    def process
      info "process disconnect"
      super
      m = /\/faye\/(player|game)\/(.+)/.match(@channel)
      if m
        case m[1]
        when 'game'
          gm = Celluloid::Actor[:"game_#{m[2]}"]
          gm.async.offline! if gm
          # locate game
        when 'player'
          pl = Celluloid::Actor[:"player_#{m[2]}"]
          pl.async.offline! if pl
          # locate player
        end
      end

      # ::Game.create(name: @name, players: @players, start: @start)
    end
  end
end

