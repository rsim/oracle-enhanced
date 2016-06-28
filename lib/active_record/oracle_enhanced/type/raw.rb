require 'active_model/type/string'

#TODO Need to consider namespace change since paremt class moved to ActiveModel
module ActiveRecord
  module OracleEnhanced
    module Type
      class Raw < ActiveModel::Type::String # :nodoc:
        def type
          :raw
        end

        def serialize(value)
          # Encode a string or byte array as string of hex codes
          if value.nil?
            super
          else
            value = value.unpack('C*')
            value.map { |x| "%02X" % x }.join
          end
        end

      end
    end
  end
end
