module ActiveRecord
  module OracleEnhanced
    module Type
      class Integer < ActiveRecord::Type::Integer # :nodoc:
        private

        def max_value
          ("9"*38).to_i
        end
      end
    end
  end
end
