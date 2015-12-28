require 'message/base'
require 'message/create'
require 'message/stop'
require 'message/game'
require 'message/player'
module Message
  extend Celluloid::Internals::Logger
  # module As; class B; end; AB = 1; constants(false).each{|s| p const_get(s) if const_get(s).is_a? Class }; end
  def parse ch, str
    subclasses.detect{|cl| cl.try_load(ch, str) }
  end

  def subclasses
    cs = constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Class } - [Message::Base]
    xs += constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Module }.map(&:subclasses).flatten
  end

  module_function :parse, :subclasses
end
