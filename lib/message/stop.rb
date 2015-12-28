module Message
  class Stop < Base
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      return nil unless hsh[:type] == 'stop'
      super
    end

    def initialize ch, hash
      super
    end

    def process
      super
      info 'stopping centre'
      Center.current.async.stop
      info 'send stop'
    end

  end
end
