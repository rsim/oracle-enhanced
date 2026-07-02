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
        # key default and the pre-8.2 implicit-UNIQUE-CONSTRAINT behavior for
        # `add_index unique: true`, so existing migrations replay unchanged.
        # The +_implicit_unique_constraint+ flag is consumed and deleted by
        # the adapter before any further processing. Callers that need a
        # constraint on Migration[8.2]+ should call
        # `add_unique_constraint :t, :col, name: :n` directly.
        class V8_1 < V8_2
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            options[:_implicit_unique_constraint] = true
            super
          end

          def add_index(table_name, column_name, **options)
            options[:_implicit_unique_constraint] = true
            super
          end

          def add_reference(table_name, *ref_names, **options)
            index = options[:index]
            if index.is_a?(Hash) && index[:unique]
              options[:index] = index.merge(_implicit_unique_constraint: true)
            end
            super
          end
          alias :add_belongs_to :add_reference

          def create_join_table(table_1, table_2, **options)
            options[:_implicit_unique_constraint] = true
            super
          end

          # Prepended onto the change_table receiver by the framework's
          # compatible_table_definition. Inject only there: the create_table
          # path is covered by the table-level flag, and Rails validates
          # per-index option keys while creating the table.
          module TableDefinition
            def index(column_name, **options)
              options[:_implicit_unique_constraint] = true if ActiveRecord::ConnectionAdapters::Table === self
              super
            end

            def references(*args, **options)
              index = options[:index]
              if ActiveRecord::ConnectionAdapters::Table === self && index.is_a?(Hash) && index[:unique]
                options[:index] = index.merge(_implicit_unique_constraint: true)
              end
              super
            end
            alias :belongs_to :references
          end
        end
      end
    end
  end
end
