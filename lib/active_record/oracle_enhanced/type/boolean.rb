module ActiveRecord
  module OracleEnhanced
    module Type
      class Boolean < ActiveModel::Type::Boolean # :nodoc:
        private

          def cast_value(value)
            # Kind of adding 'n' and 'N' to  `FALSE_VALUES`
            if ["n", "N"].include?(value)
              false
            else
              super
            end
          end
      end
    end
  end
end
