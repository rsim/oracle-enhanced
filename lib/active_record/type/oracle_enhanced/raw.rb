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
          return super if value.nil?
          Data.new(super)
        end

        def deserialize(value)
          # Data wraps the attribute's own String, so cast a copy to keep
          # in-place changes to the attribute detectable.
          super(value.is_a?(Data) ? value.to_s : value)
        end

        class Data # :nodoc:
          def initialize(value)
            @value = value
          end

          def to_s
            @value
          end

          # Encode the bytes as a string of hex codes, which Oracle converts to RAW
          def to_hex
            @value.unpack1("H*").upcase
          end

          def ==(other)
            other = other.to_s if other.is_a?(Data)
            @value == other
          end
          alias eql? ==

          def hash
            @value.hash
          end
        end
      end
    end
  end
end
