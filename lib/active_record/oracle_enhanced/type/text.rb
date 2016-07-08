require 'active_model/type/string'

module ActiveRecord
  module OracleEnhanced
    module Type
      class Text < ActiveModel::Type::Text # :nodoc:

        def changed_in_place?(raw_old_value, new_value)
          #TODO: Needs to find a way not to cast here.
          raw_old_value = cast(raw_old_value)
          super
        end

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
