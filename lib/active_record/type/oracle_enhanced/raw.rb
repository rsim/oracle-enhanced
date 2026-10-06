# frozen_string_literal: true

require "active_model/type/string"

module ActiveRecord
  module Type
    module OracleEnhanced
      class Raw < ActiveModel::Type::String # :nodoc:
        def type
          :raw
        end

        def deserialize(value)
          value.is_a?(HEXData) ? value.raw_binary_string : super
        end

        def serialize(value)
          # Encode a string or byte array as string of hex codes
          if value.nil?
            super
          else
            HEXData.from_binary_string(value)
          end
        end

        class HEXData < ::String
          def self.from_binary_string(str)
            new(str.unpack1("H*"))
          end

          def raw_binary_string
            (0..length - 2).step(2).reduce(::String.new(capacity: length / 2, encoding: Encoding::BINARY)) do |data, i|
              data << self[i, 2].hex
            end
          end

          OCI8::BindType::Mapping[self] = OCI8::BindType::String
        end
      end
    end
  end
end
