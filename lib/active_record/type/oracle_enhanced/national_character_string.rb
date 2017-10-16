# frozen_string_literal: true

require "active_model/type/string"

module ActiveRecord
  module Type
    module OracleEnhanced
      class NationalCharacterString < ActiveRecord::Type::OracleEnhanced::String # :nodoc:
        def serialize(value)
          return unless value
          Data.new(super)
        end

        class Data # :nodoc:
          def initialize(value)
            @value = value
          end

          def to_s
            @value
          end
        end
      end
    end
  end
end
