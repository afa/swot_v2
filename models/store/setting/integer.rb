module Store
  class Setting
    class String < Store::Setting::Base

      attribute :value, Type::Integer
    end
  end
end

