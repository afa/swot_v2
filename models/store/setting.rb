require 'ostruct'
require 'store/setting/string'
require 'store/setting/integer'
require 'store/setting/boolean'
require 'store/setting/big_decimal'
class Store::Setting
  attr_accessor :current, :game_uuid

  def initialize params = {}
    @current = OpenStruct.new
  end
end
