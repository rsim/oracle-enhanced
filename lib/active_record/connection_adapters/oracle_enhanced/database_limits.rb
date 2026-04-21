# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseLimits
        # Keep the legacy constant available via direct access while steering
        # callers toward the dynamic, connection-specific max_identifier_length.
        # A deprecated constant proxy does not fit here because the replacement
        # is a method, not another constant.
        #
        # Note: direct reads (+DatabaseLimits::IDENTIFIER_MAX_LENGTH+) still work;
        # reflection APIs (+const_defined?+, +defined?+, +.constants+) do not see
        # it because nothing is actually declared.
        def self.const_missing(name)
          if name == :IDENTIFIER_MAX_LENGTH
            OracleEnhanced.deprecator.deprecation_warning(
              "ActiveRecord::ConnectionAdapters::OracleEnhanced::DatabaseLimits::IDENTIFIER_MAX_LENGTH",
              "use `max_identifier_length` instead"
            )
            30
          else
            super
          end
        end

        # the maximum length of a sequence name
        def sequence_name_length
          max_identifier_length
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
