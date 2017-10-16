# frozen_string_literal: true

module ActiveRecord
  module Type
    module OracleEnhanced
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
