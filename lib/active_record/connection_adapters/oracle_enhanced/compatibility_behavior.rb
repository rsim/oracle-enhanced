# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        # Migration[8.2]+ migrations default to an Oracle identity primary
        # key when the server supports it. Schema loads (plain and versioned
        # `ActiveRecord::Schema[x.y].define`, both including
        # +ActiveRecord::Schema::Definition+) and direct adapter calls keep
        # the adapter's pre-existing sequence default so that schema dumps
        # written by older releases reload unchanged. An explicit
        # `identity:` value always wins.
        class V8_2 < Base
          def create_table(table_name, **options)
            options[:identity] = true if default_to_identity?(options)
            super
          end

          private
            def default_to_identity?(options)
              return false if migration.is_a?(ActiveRecord::Schema::Definition)
              return false if options.key?(:identity)
              return false if options[:sequence_name] || options[:sequence_start_value]
              return false if options[:primary_key_trigger]
              return false if options.fetch(:id, :primary_key) != :primary_key
              return false if options[:primary_key].is_a?(Array)
              connection.supports_identity_columns?
            end
        end

        # Migration[8.1] and earlier keep the pre-8.2 sequence-backed primary
        # key default so existing migrations replay unchanged.
        class V8_1 < V8_2
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            super
          end
        end
      end
    end
  end
end
