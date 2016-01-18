require 'store/setting/base'
module Store
  class Setting
    class String < Setting::Base

      attribute :value, Type::String
    end
  end
end
