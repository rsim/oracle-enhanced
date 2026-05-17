# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module MigrationCompatibility # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::Versioned

        module V8_2
          def create_table(table_name, **options)
            options[:identity] = true if oracle_enhanced_default_to_identity?(options)
            super
          end

          private
            def oracle_enhanced_default_to_identity?(options)
              return false if options.key?(:identity)
              return false if options[:sequence_name] || options[:sequence_start_value]
              return false if options.fetch(:id, :primary_key) != :primary_key
              return false if options[:primary_key].is_a?(Array)
              connection.supports_identity_columns?
            end
        end

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
