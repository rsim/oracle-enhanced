# frozen_string_literal: true

require "active_model/type/string"

module ActiveRecord
  module Type
    module OracleEnhanced
      class CharacterString < ActiveRecord::Type::OracleEnhanced::String # :nodoc:
        def serialize(value)
          return unless value
          Data.new(super, self.limit)
        end

        class Data # :nodoc:
          def initialize(value, limit)
            @value = value
            @limit = limit
          end

          def to_s
            @value
          end

          def to_character_str
            len = @value.to_s.length
            if len < @limit
              "%-#{@limit}s" % @value
            else
              @value
            end
          end
        end
      end
    end
  end
end
