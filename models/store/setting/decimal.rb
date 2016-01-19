module Store
  class Setting
    class BigDecimal < Store::Setting::Base
      include Ohm::DataTypes

      attribute :value, Type::Decimal

    end
  end
end
