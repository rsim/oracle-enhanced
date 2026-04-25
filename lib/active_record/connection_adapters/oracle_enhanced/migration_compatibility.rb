# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module MigrationCompatibility # :nodoc: all
        module V8_2
          def create_table(table_name, id: :primary_key, primary_key: nil, **options, &block)
            if !options.key?(:identity) &&
               connection.supports_identity_columns? &&
               id == :primary_key &&
               !primary_key.is_a?(Array)
              options[:identity] = true
            end
            super
          end
        end

        def self.module_for(migration_class)
          compat = ActiveRecord::Migration::Compatibility
          if migration_class <= compat::V8_2 && !(migration_class <= compat::V8_1)
            V8_2
          end
        end
      end
    end
  end
end
