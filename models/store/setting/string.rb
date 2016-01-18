require 'store/setting/base'
module Store
  class Setting
    class String < Setting::Base
      include Ohm::DataTypes

      attribute :value
    end
  end
end
