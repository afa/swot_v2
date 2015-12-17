require "game"
module Message
  class Create
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'create'
      self.new hsh
    end

    def initialize hash
      @name = hash[:name] if hash[:name]
    end

    def process
      Game.new
    end
  end
end
