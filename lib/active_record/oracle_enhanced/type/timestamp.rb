module ActiveRecord
  module OracleEnhanced
    module Type
      class Timestamp < ActiveRecord::Type::Value # :nodoc:
        def type
          :timestamp
        end

        def type_cast_from_user(value)  
          if String === value
            Time.parse(value) rescue nil
          else
            super
          end
        end
      end
    end
  end
end
