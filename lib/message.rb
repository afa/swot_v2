require 'message/create'
module Message
  # module As; class B; end; AB = 1; constants(false).each{|s| p const_get(s) if const_get(s).is_a? Class }; end
  def parse str
    subclasses.detect{|cl| cl.try_load(str) }
  end

  def subclasses
    constants(false).map{|c| const_get(c) }.select{|c| c.is_a? Class }
  end

  module_function :parse, :subclasses
end
