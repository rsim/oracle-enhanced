require 'active_model/type/string'

module ActiveRecord
  module OracleEnhanced
    module Type
      class NationalCharacterString < ActiveRecord::OracleEnhanced::Type::String # :nodoc:

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
