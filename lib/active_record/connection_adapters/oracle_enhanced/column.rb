# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        delegate :virtual, to: :sql_type_metadata, allow_nil: true

        def initialize(name, default, sql_type_metadata = nil, null = true, comment: nil) #:nodoc:
          super(name, default, sql_type_metadata, null, comment: comment)
        end

        def virtual?
          virtual
        end
      end
    end
  end
end
