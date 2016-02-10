module Message
  class Base
    attr_accessor :at
    include Celluloid::Internals::Logger
    def self.try_load(ch, hsh)
      p 'try_load', ch, hash
      new ch, hsh
    end

    def initialize ch, hash = {}
      self.at = ('%10.6f' % Time.now).to_f
    end

    def process
    end
  end
end

