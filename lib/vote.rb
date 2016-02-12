class Vote
  attr_accessor :player, :result, :active

  def initialize params = {}
    @player = params[:player]
    @result = params[:result]
    @active = nil
  end
end
