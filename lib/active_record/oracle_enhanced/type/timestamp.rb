module ActiveRecord
  module OracleEnhanced
    module Type
      class Timestamp < ActiveRecord::Type::Value # :nodoc:
        def type
          :timestamp
        end
      end
    end
  end
end
