# frozen_string_literal: true

require "active_model/type/string"

module ActiveRecord
  module Type
    module OracleEnhanced
      class Raw < ActiveModel::Type::String # :nodoc:
        def type
          :raw
        end

        def serialize(value)
          # Encode a string or byte array as string of hex codes
          if value.nil?
            super
          else
            value = value.unpack("C*")
            value.map { |x| "%02X" % x }.join
          end
        end
      end
    end
  end
end
