# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        # A behavior applies to migrations declaring its own version and older:
        # Migration[8.2]+ resolves to V8_2, Migration[8.1] and earlier to V8_1.
        class V8_2 < Base; end

        # Migration[8.1] and earlier keep the pre-8.2 implicit-UNIQUE-CONSTRAINT
        # behavior for `add_index unique: true`, so existing migrations replay
        # unchanged. The +_implicit_unique_constraint+ flag is consumed and
        # deleted by the adapter before any further processing. Callers that
        # need a constraint on Migration[8.2]+ should call
        # `add_unique_constraint :t, :col, name: :n` directly.
        class V8_1 < V8_2
          def create_table(table_name, **options)
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
