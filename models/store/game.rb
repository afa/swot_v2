class Store::Game < Ohm::Model
  attribute :name
  attribute :uuid
  unique :uuid

  def initialize params = {}
    self.name = params[:name] if params[:name]
    self.uuid = params[:uuid] if params[:uuid]
  end
end
