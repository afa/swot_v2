module Store
  class Statement < Ohm::Model
    include Ohm::DataTypes
    include Ohm::Callbacks

    attribute :game_uuid
    attribute :stage
    attribute :step
    attribute :value
    attribute :author
    attribute :votes, Type::Hash

  end
end
