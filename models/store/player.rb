class Store::Player < Ohm::Model
  include Ohm::DataTypes
  attribute :uuid
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
end
