# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        extend Migration::CompatibilityBehavior::Resolver

        # Migration[8.1] and earlier keep the pre-8.2 defaults so existing
        # migrations replay unchanged: a sequence-backed primary key, and a
        # UNIQUE CONSTRAINT behind every `unique: true` index. An explicit
        # `identity:` value always wins. While a migration is being reverted
        # the operations are only recorded, so no constraint is added; the
        # recorded drop_table / remove_index remove it with the index.
        class V8_1 < Migration::CompatibilityBehavior
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            definition = nil
            super(table_name, **options) do |t|
              definition = t
              yield t if block_given?
            end
            add_implicit_unique_constraints(definition)
          end

          def create_join_table(table_1, table_2, **options)
            definition = nil
            super(table_1, table_2, **options) do |t|
              definition = t
              yield t if block_given?
            end
            add_implicit_unique_constraints(definition)
          end

          def add_index(table_name, column_name, **options)
            # With if_not_exists: the adapter skips an existing index, and so
            # does the constraint.
            exists = options[:if_not_exists] && !migration.reverting? &&
              connection.index_exists?(proper_table_name(table_name), column_name, **options.slice(:name))
            super
            add_implicit_unique_constraint(table_name, column_name, **options) unless exists
          end

          def add_reference(table_name, ref_name, **options)
            super
            columns, index_options = V8_1.reference_index(proper_table_name(table_name), ref_name, options)
            add_implicit_unique_constraint(table_name, columns, **index_options) if columns
          end
          alias :add_belongs_to :add_reference

          # The columns and options of the unique index that add_reference /
          # t.references created for +ref_name+, or nil when it created none.
          # A polymorphic index carries the name Rails gives it unless the
          # migration version uses the legacy column-based name.
          def self.reference_index(table_name, ref_name, options)
            index = options[:index]
            return unless index.is_a?(Hash) && index[:unique]
            index = index.dup
            if options[:polymorphic]
              index[:name] ||= "index_#{table_name}_on_#{ref_name}" unless options[:_uses_legacy_reference_index_name]
              [["#{ref_name}_type", "#{ref_name}_id"], index]
            else
              [["#{ref_name}_id"], index]
            end
          end

          # Prepended onto the Table that change_table yields, whose index and
          # references call the connection directly instead of the operations
          # above. While reverting, that connection is the CommandRecorder.
          module TableDefinition
            def index(column_name, **options)
              super
              add_implicit_unique_constraint(column_name, **options)
            end

            def references(*ref_names, **options)
              super
              ref_names.each do |ref_name|
                columns, index_options = V8_1.reference_index(name, ref_name, options)
                add_implicit_unique_constraint(columns, **index_options) if columns
              end
            end
            alias :belongs_to :references

            private
              def add_implicit_unique_constraint(columns, **index_options)
                return unless ActiveRecord::ConnectionAdapters::Table === self && !@base.respond_to?(:revert)
                @base.add_implicit_unique_constraint(name, columns, **index_options)
              end
          end

          private
            def add_implicit_unique_constraint(table_name, columns, **index_options)
              return if migration.reverting?
              connection.add_implicit_unique_constraint(proper_table_name(table_name), columns, **index_options)
            end

            def add_implicit_unique_constraints(definition)
              return if migration.reverting? || definition.nil?
              connection.add_implicit_unique_constraints(definition)
            end

            def proper_table_name(table_name)
              migration.proper_table_name(table_name, migration.table_name_options)
            end
        end
      end
    end
  end
end
