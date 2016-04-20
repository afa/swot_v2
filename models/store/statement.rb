module Store
  class Statement < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribute :game_uuid
    attribute :uuid
    attribute :stage
    attribute :step, Type::Integer
    attribute :value
    attribute :author
    attribute :votes, Type::Hash
    attribute :status
    attribute :importances, Type::Array

    index :game_uuid
    index :uuid
    index :status

  end
end
