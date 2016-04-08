module Store
  class AdminLog < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribude :game_uuid
    attribute :data, Type::Hash
    attribute :created_at, Type::DateTime
    index :game_uuid
    
  end
end
