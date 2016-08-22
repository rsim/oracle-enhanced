module ActiveRecord
  module OracleEnhanced
    module Type
      class Boolean < ActiveModel::Type::Boolean # :nodoc:
        # Add 'N' as FALSE_VALUES
        FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', 'n', 'N'].to_set

        private

        def cast_value(value)
          # Not calling super to use its own `FALSE_VALUES`
          if value == ''
            nil
          else
            !FALSE_VALUES.include?(value)
          end
        end

      end
    end
  end
end
