class Vote
  attr_accessor :player, :result, :active

  def as_json
    { player: @player, result: @result }
  end

  def initialize params = {}
    @player = params[:player]
    @result = params[:result]
    @active = nil
  end
end
