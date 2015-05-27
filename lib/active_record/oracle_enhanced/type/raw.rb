require 'active_record/type/string'

module ActiveRecord
  module OracleEnhanced
    module Type
      class Raw < ActiveRecord::Type::String # :nodoc:
        def type
          :raw
        end
      end
    end
  end
end
