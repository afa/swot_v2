module Message
  class Stop
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'stop'
      super
    end

    def initialize hash
      super
    end

    def process
      super
      Center.async.terminate
    end

  end
end
