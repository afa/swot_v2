module Message
  class Stop < Base
    def self.try_load(hsh)
      return nil unless hsh[:type] == 'stop'
      super
    end

    def initialize hash
      super
    end

    def process
      super
      info 'stopping centre'
      Center.current.async.stop
    end

  end
end
