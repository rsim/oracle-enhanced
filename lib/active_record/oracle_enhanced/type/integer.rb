module ActiveRecord
  module OracleEnhanced
    module Type
      class Integer < ActiveModel::Type::Integer # :nodoc:
        private

          def max_value
            ("9" * 38).to_i
          end
      end
    end
  end
end
