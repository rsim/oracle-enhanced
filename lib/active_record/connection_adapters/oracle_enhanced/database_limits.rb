# frozen_string_literal: true

require "active_support/deprecation"

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseLimits
        # maximum length of Oracle identifiers
        IDENTIFIER_MAX_LENGTH = 30

        def table_alias_length # :nodoc:
          IDENTIFIER_MAX_LENGTH
        end

        # the maximum length of a table name
        def table_name_length
          IDENTIFIER_MAX_LENGTH
        end
        deprecate :table_name_length, deprecator: ActiveSupport::Deprecation.new

        # the maximum length of a column name
        def column_name_length
          IDENTIFIER_MAX_LENGTH
        end
        deprecate :column_name_length, deprecator: ActiveSupport::Deprecation.new

        # the maximum length of an index name
        # supported by this database
        def index_name_length
          IDENTIFIER_MAX_LENGTH
        end

        # the maximum length of a sequence name
        def sequence_name_length
          IDENTIFIER_MAX_LENGTH
        end

        # To avoid ORA-01795: maximum number of expressions in a list is 1000
        # tell ActiveRecord to limit us to 1000 ids at a time
        def in_clause_length
          1000
        end
      end
    end
  end
end
