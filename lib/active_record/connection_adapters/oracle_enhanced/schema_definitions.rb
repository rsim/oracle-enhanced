# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module ColumnMethods
        def primary_key(name, type = :primary_key, **options)
          # This is a placeholder for future :auto_increment support
          super
        end

        [
          :raw,
          :timestamptz,
          :timestampltz,
          :ntext
        ].each do |column_type|
          module_eval <<-CODE, __FILE__, __LINE__ + 1
            def #{column_type}(*args, **options)
              args.each { |name| column(name, :#{column_type}, **options) }
            end
          CODE
        end
      end

      class ReferenceDefinition < ActiveRecord::ConnectionAdapters::ReferenceDefinition # :nodoc:
        def initialize(
          name,
          polymorphic: false,
          index: true,
          foreign_key: false,
          type: :integer,
          **options)
          super
        end
      end

      class SynonymDefinition < Struct.new(:name, :table_owner, :table_name) # :nodoc:
      end

      class IndexDefinition < ActiveRecord::ConnectionAdapters::IndexDefinition
        attr_accessor :parameters, :statement_parameters, :tablespace

        def initialize(table, name, unique, columns, orders, type, parameters, statement_parameters, tablespace)
          @parameters = parameters
          @statement_parameters = statement_parameters
          @tablespace = tablespace
          super(table, name, unique, columns, orders: orders, type: type)
        end
      end

      UniqueConstraintDefinition = Struct.new(:table_name, :column, :options) do
        def name
          options[:name]
        end

        def deferrable
          options[:deferrable]
        end

        def using_index
          options[:using_index]
        end

        def export_name_on_schema_dump?
          !ActiveRecord::SchemaDumper.unique_ignore_pattern.match?(name) if name
        end

        def defined_for?(name: nil, column: nil, **options)
          options = options.slice(*self.options.keys)

          (name.nil? || self.name == name.to_s) &&
            (column.nil? || Array(self.column).map(&:to_s) == Array(column).map(&:to_s)) &&
            options.all? { |k, v| self.options[k].to_s == v.to_s }
        end
      end

      class TableDefinition < ActiveRecord::ConnectionAdapters::TableDefinition
        include OracleEnhanced::ColumnMethods

        attr_accessor :tablespace, :organization
        attr_reader :unique_constraints

        def initialize(
          conn,
          name,
          temporary: false,
          options: nil,
          as: nil,
          tablespace: nil,
          organization: nil,
          comment: nil,
          **
        )
          @tablespace = tablespace
          @organization = organization
          @unique_constraints = []
          super(conn, name, temporary: temporary, options: options, as: as, comment: comment)
        end

        def new_column_definition(name, type, **options) # :nodoc:
          if type == :virtual
            raise "No virtual column definition found." unless options[:as]
            type = options[:type]
          end
          super
        end

        def references(*args, **options)
          super(*args, type: :integer, **options)
        end
        alias :belongs_to :references

        def unique_constraint(column_name, **options)
          unique_constraints << new_unique_constraint_definition(column_name, options)
        end

        def new_unique_constraint_definition(column_name, options) # :nodoc:
          options = @conn.unique_constraint_options(name, column_name, options)
          UniqueConstraintDefinition.new(name, column_name, options)
        end

        private
          def valid_column_definition_options
            super + [ :as, :sequence_name, :sequence_start_value, :type, :identity, :primary_key_trigger, :trigger_name ]
          end
      end

      class AlterTable < ActiveRecord::ConnectionAdapters::AlterTable
        attr_reader :unique_constraint_adds, :constraint_validations

        def initialize(td)
          super
          @unique_constraint_adds = []
          @constraint_validations = []
        end

        def add_unique_constraint(column_name, options)
          @unique_constraint_adds << @td.new_unique_constraint_definition(column_name, options)
        end

        def validate_constraint(name)
          @constraint_validations << name
        end
      end

      class Table < ActiveRecord::ConnectionAdapters::Table
        include OracleEnhanced::ColumnMethods

        def unique_constraint(...)
          @base.add_unique_constraint(name, ...)
        end

        def remove_unique_constraint(...)
          @base.remove_unique_constraint(name, ...)
        end

        def validate_constraint(...)
          @base.validate_constraint(name, ...)
        end

        def validate_check_constraint(...)
          @base.validate_check_constraint(name, ...)
        end

        def validate_foreign_key(...)
          @base.validate_foreign_key(name, ...)
        end
      end
    end
  end
end
