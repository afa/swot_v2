require 'ostruct'
class State
  include Celluloid
  attr_accessor :game_uuid, :game, :players, :statements

  def initialize params = {}
    @game_uuid = params[:game_uuid]
  end
