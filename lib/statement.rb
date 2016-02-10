class Statement
  include Celluloid::Internals::Logger

  attr_accessor :value, :author, :replaces, :uuid, :position, :game_uuid, :stage, :step, :votes, :importances

  def initialize params = {}
    @value = params[:value]
    @replaces = params[:replaces]
    @uuid = params[:uuid]
    @position = params[:position] if params[:position]
    @game_uuid = params[:game_uuid]
    @stage = params[:stage]
    @step = params[:step]
    @votes = []
    @importances = []
  end

end
