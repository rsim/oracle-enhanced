module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced

      class SynonymDefinition < Struct.new(:name, :table_owner, :table_name, :db_link) #:nodoc:
      end

      class IndexDefinition < ActiveRecord::ConnectionAdapters::IndexDefinition
        attr_accessor :parameters, :statement_parameters, :tablespace

        def initialize(table, name, unique, columns, lengths, orders, where, type, using, parameters, statement_parameters, tablespace)
          @parameters = parameters
          @statement_parameters = statement_parameters
          @tablespace = tablespace
          super(table, name, unique, columns, lengths, orders, where, type, using)
        end
      end

      class ColumnDefinition < ActiveRecord::ConnectionAdapters::ColumnDefinition

      end

      class TableDefinition < ActiveRecord::ConnectionAdapters::TableDefinition
        attr_accessor :tablespace, :organization
        def initialize(name, temporary = false, options = nil, as = nil, tablespace = nil, organization = nil, comment: nil)
          @tablespace = tablespace
          @organization = organization
          super(name, temporary, options, as, comment: comment)
        end

        def virtual(* args)
          options = args.extract_options!
          column_names = args
          column_names.each { |name| column(name, :virtual, options) }
        end

        def column(name, type, options = {})
          if type == :virtual
            default = {:type => options[:type]}
            if options[:as]
              default[:as] = options[:as]
            else
              raise "No virtual column definition found."
            end
            options[:default] = default
          end
          super(name, type, options)
        end

        private
        def create_column_definition(name, type)
          OracleEnhanced::ColumnDefinition.new name, type
        end

      end

    end
  end
end
