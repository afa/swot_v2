module Store
  class PlayerLog < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribude :game_uuid
    attribude :uuid
    index :game_uuid
    index :uuid
    
  end
end

