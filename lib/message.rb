require 'message/base'
require 'message/create'
require 'message/stop'
require 'message/game'
require 'message/player'
require 'message/connect'
require 'message/disconnect'
module Message
  extend Celluloid::Internals::Logger
  # module As; class B; end; AB = 1; constants(false).each{|s| p const_get(s) if const_get(s).is_a? Class }; end
  def parse ch, str
    subclasses.detect do |cl|
      dat = cl.try_load(ch, str)
      dat
    end
  end

  def subclasses
    cs = constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Class } - [Message::Base]
    cs += (constants(false).map{|c| const_get(c) }.select{|c| not c.is_a? Class }).map(&:subclasses).flatten
    cs
  end

  module_function :parse, :subclasses
end
