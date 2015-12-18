module Message
  class Base
    attr_accessor :at
    include Celluloid::Internals::Logger
    def self.try_load(hsh)
      new hsh
    end

    def initialize hash = {}
      self.at = ('%10.6f' % Time.now).to_f
    end

    def process
    end
  end
end

