class Store::Game < Ohm::Model
  include Ohm::DataTypes
  attribute :name
  attribute :uuid
  attribute :company
  attribute :country
  attribute :description
  attribute :industry
  attribute :start_at, Type::Integer
  attribute :state
  attribute :time_zone
  attribute :mongo_id
  index :mongo_id
  index :uuid
  unique :uuid

  def as_json
    {
      name: name,
      uuid: uuid,
      start_at: start_at.to_i,
      state: state,
      mongo_id: mongo_id,
      settings: settings.as_json,
      players: players.as_json
    }
  end

  # def initialize params = {}
  #   # self.name = params[:name] if params[:name]
  #   # self.uuid = params[:uuid] if params[:uuid]
  # end
end
