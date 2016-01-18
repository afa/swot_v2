require 'ohm/contrib'
module Store
  class Setting
    class Base < Ohm::Model
      include Ohm::DataTypes

      attribute :name
      attribute :game_uuid
    end
  end
end
