module Store
  class AdminLog < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribute :game_uuid
    attribute :data, Type::Hash
    attribute :created_at, Type::Timestamp
    index :game_uuid
    
  end
end
