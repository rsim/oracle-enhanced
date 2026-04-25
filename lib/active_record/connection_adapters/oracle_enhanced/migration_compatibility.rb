# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module MigrationCompatibility # :nodoc: all
        module IdentityPrimaryKey
          def create_table(table_name, **options, &block)
            if !options.key?(:identity) && connection.supports_identity_columns?
              options[:identity] = true
            end
            super
          end
        end

        def self.module_for(migration_class)
          compat = ActiveRecord::Migration::Compatibility
          if migration_class <= compat::V8_2 && !(migration_class <= compat::V8_1)
            IdentityPrimaryKey
          end
        end
      end
    end
  end
end
