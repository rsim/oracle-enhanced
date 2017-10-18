# frozen_string_literal: true

module ActiveRecord
  module Type
    module OracleEnhanced
      class TimestampTz < ActiveRecord::Type::DateTime
        def type
          :timestamptz
        end

        class Data < DelegateClass(::Time) # :nodoc:
        end

        def serialize(value)
          case value = super
          when ::Time
            Data.new(value)
          else
            value
          end
        end
      end
    end
  end
end
