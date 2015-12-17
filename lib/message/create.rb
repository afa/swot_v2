require "game"
module Message
  class Create < Base
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'create'
      super
    end

    def initialize hash
      super
      @name = hash[:name] if hash[:name]
    end

    def process
      super
      Game.new
    end
  end
end
