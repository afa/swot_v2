module Message
  class Base
    def self.try_load(hsh)
      self.new hsh
    end

    def initialize hash
    end

    def process
    end
  end
end

