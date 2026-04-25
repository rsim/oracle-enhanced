# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        delegate :virtual, to: :sql_type_metadata, allow_nil: true

        def initialize(name, cast_type, default, sql_type_metadata = nil, null = true, comment: nil, identity: false) # :nodoc:
          super(name, cast_type, default, sql_type_metadata, null, comment: comment)
          @identity = identity
        end

        def virtual?
          virtual
        end

        def auto_incremented_by_db?
          @identity
        end

        def ==(other)
          super && other.is_a?(Column) && auto_incremented_by_db? == other.auto_incremented_by_db?
        end
        alias :eql? :==

        def hash
          [super, @identity].hash
        end
      end
    end
  end
end
