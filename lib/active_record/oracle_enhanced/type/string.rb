require 'active_model/type/string'

module ActiveRecord
  module OracleEnhanced
    module Type
      class String < ActiveModel::Type::String # :nodoc:
        def changed?(old_value, new_value, _new_value_before_type_cast)
          if old_value.nil?
            new_value = nil if new_value == ""
            old_value != new_value
          else
            super
          end
        end

        def changed_in_place?(raw_old_value, new_value)
          if raw_old_value.nil?
            new_value = nil if new_value == ''
            raw_old_value != new_value
          else
            super
          end
        end

      end
    end
  end
end
