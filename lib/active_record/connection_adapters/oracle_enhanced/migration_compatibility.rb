# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module MigrationCompatibility # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::Versioned

        module V8_1
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            super
          end
        end
      end
    end
  end
end
