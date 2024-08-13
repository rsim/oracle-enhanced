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

      class TableDefinition < ActiveRecord::ConnectionAdapters::TableDefinition
        include OracleEnhanced::ColumnMethods

        attr_accessor :tablespace, :organization
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

        private
          def valid_column_definition_options
            super + [ :as, :sequence_name, :sequence_start_value, :type ]
          end
      end

      class AlterTable < ActiveRecord::ConnectionAdapters::AlterTable
      end

      class Table < ActiveRecord::ConnectionAdapters::Table
        include OracleEnhanced::ColumnMethods
      end
    end
  end
end
