module Store
  class AuditLog < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribude :game_uuid
    index :game_uuid
    
  end
end

