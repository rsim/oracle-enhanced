# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        delegate :virtual, to: :sql_type_metadata, allow_nil: true

        def initialize(*, identity: false, trigger_assigned: false, **) # :nodoc:
          super
          @identity = identity
          @trigger_assigned = trigger_assigned
        end

        def init_with(coder) # :nodoc:
          super
          @identity = coder["identity"] unless coder["identity"].nil?
          @trigger_assigned = coder["trigger_assigned"] unless coder["trigger_assigned"].nil?
        end

        def encode_with(coder) # :nodoc:
          super
          coder["identity"] = @identity
          coder["trigger_assigned"] = @trigger_assigned
        end

        def virtual?
          virtual
        end

        def auto_incremented_by_db?
          @identity
        end

        def auto_populated?
          super || @trigger_assigned
        end

        def ==(other)
          other.is_a?(Column) &&
            super &&
            auto_incremented_by_db? == other.auto_incremented_by_db? &&
            @trigger_assigned == other.instance_variable_get(:@trigger_assigned)
        end
        alias :eql? :==

        def hash
          [super, @identity, @trigger_assigned].hash
        end
      end
    end
  end
end
