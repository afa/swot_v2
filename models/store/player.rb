class Store::Player < Ohm::Model
  include Ohm::DataTypes
  attribute :uuid
  attribute :mongo_id
  attribute :state
  attribute :game_uuid
  attribute :name
  attribute :email
  attribute :score, Type::Decimal
  attribute :rank, Type::Decimal
  attribute :order, Type::Integer
  index :uuid
  index :game_uuid
  index :order

  def as_json
    {
      uuid: uuid,
      id: mongo_id,
      state: state,
      game_uuid: game_uuid,
      name: name,
      email: email,
      order: order,
      score: score,
      rank: rank
    }
  end
end
