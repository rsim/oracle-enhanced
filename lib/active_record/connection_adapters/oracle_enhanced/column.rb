# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        delegate :virtual, to: :sql_type_metadata, allow_nil: true

        def initialize(name, default, sql_type_metadata = nil, null = true, comment: nil) # :nodoc:
          super(name, default, sql_type_metadata, null, comment: comment)
        end

        def virtual?
          virtual
        end

        def auto_incremented_by_db?
          # TODO: Identify if a column is the primary key and is auto-incremented (e.g. by a sequence)
          super
        end
      end
    end
  end
end
