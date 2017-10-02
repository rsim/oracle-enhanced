# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced
      class TypeMetadata < DelegateClass(SqlTypeMetadata) # :nodoc:
        def initialize(type_metadata)
          super(type_metadata)
        end
      end
    end
  end
end
