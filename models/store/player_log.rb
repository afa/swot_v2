module Store
  class PlayerLog < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribute :game_uuid
    attribute :uuid
    attribute :data, Type::Hash
    index :game_uuid
    index :uuid
    
  end
end

