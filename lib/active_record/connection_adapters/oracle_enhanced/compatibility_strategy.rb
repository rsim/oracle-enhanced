# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityStrategy # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityStrategy
        extend Base::Resolver

        # Migration[8.2]+ migrations default to an Oracle identity primary
        # key when the server supports it. `Schema.define` (whose migration
        # class is +ActiveRecord::Schema+) and direct adapter calls keep
        # the adapter's pre-existing sequence default so that schema dumps
        # written by older releases reload unchanged. An explicit
        # `identity:` value always wins.
        class V8_2 < Base
          def create_table(table_name, **options)
            options[:identity] = true if default_to_identity?(options)
            yield table_name, **options
          end

          private
            def default_to_identity?(options)
              return false if migration.is_a?(ActiveRecord::Schema)
              return false if options.key?(:identity)
              return false if options[:sequence_name] || options[:sequence_start_value]
              return false if options.fetch(:id, :primary_key) != :primary_key
              return false if options[:primary_key].is_a?(Array)
              connection.supports_identity_columns?
            end
        end

        # Migration[8.1] and earlier keep the legacy sequence-backed primary
        # key default and the legacy implicit-UNIQUE-CONSTRAINT behavior for
        # `add_index unique: true`, so existing migrations replay unchanged.
        # The +_implicit_unique_constraint+ flag is consumed and deleted by
        # the adapter before any further processing. Callers that need a
        # constraint on Migration[8.2]+ should call
        # `add_unique_constraint :t, :col, name: :n` directly.
        class V8_1 < V8_2
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            options[:_implicit_unique_constraint] = true
            yield table_name, **options
          end

          def add_index(table_name, column_name, **options)
            options[:_implicit_unique_constraint] = true
            yield table_name, column_name, **options
          end
        end
      end
    end
  end
end
