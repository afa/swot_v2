module Store
  class Setting
    class Decimal < Store::Setting::Base
      include Ohm::DataTypes

      attribute :value, Type::Decimal

    end
  end
end
