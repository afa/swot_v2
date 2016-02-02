class Store::Player < Ohm::Model
  attribute :uuid
  attribute :state
  attribute :game_uuid
  attribute :name
  attribute :email
  attribute :order
  index :uuid
  index :game_uuid
  index :order
end
