# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        # A behavior covers migrations declaring its own version and older:
        # Migration[8.1] and earlier resolve to V8_1. Migration[8.2] and later
        # resolve to the no-op base, so the adapter's own defaults apply.

        # Migration[8.1] and earlier keep the pre-8.2 defaults so existing
        # migrations replay unchanged: a sequence-backed primary key, and the
        # implicit-UNIQUE-CONSTRAINT behavior for `add_index unique: true`.
        # An explicit `identity:` value always wins. The
        # +_implicit_unique_constraint+ flag is consumed and deleted by the
        # adapter before any further processing. Callers that need a
        # constraint on Migration[8.2]+ should call
        # `add_unique_constraint :t, :col, name: :n` directly.
        class V8_1 < Base
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
