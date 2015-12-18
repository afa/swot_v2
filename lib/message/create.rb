require "game"
module Message
  class Create < Base
    include Celluloid::Internals::Logger
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'create'
      new(hsh) #.tap{|x| Celluloid::Internals::Logger.info x.inspect }
    end

    def initialize hash = {}
      super
      @name = hash[:name] if hash[:name]
    end

    def process
      super
      Game.new
    end
  end
end
