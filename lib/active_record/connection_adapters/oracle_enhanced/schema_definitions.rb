module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced

      class ForeignKeyDefinition < ActiveRecord::ConnectionAdapters::ForeignKeyDefinition
        def name
          if options[:name].length > OracleEnhancedAdapter::IDENTIFIER_MAX_LENGTH
            ActiveSupport::Deprecation.warn "Foreign key name #{options[:name]} is too long. It will not get shorten in later version of Oracle enhanced adapter"
            'c'+Digest::SHA1.hexdigest(options[:name])[0,OracleEnhancedAdapter::IDENTIFIER_MAX_LENGTH-1]
          else
            options[:name]
          end
        end
      end

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
            elsif options[:default]
              warn "[DEPRECATION] virtual column `:default` option is deprecated.  Please use `:as` instead."
              default[:as] = options[:default]
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

      class AlterTable < ActiveRecord::ConnectionAdapters::AlterTable
        def add_foreign_key(to_table, options)
          @foreign_key_adds << OracleEnhanced::ForeignKeyDefinition.new(name, to_table, options)
        end
      end

      class Table < ActiveRecord::ConnectionAdapters::Table
        def foreign_key(to_table, options = {})
          ActiveSupport::Deprecation.warn "`foreign_key` option will be deprecated. Please use `references` option"
          to_table = to_table.to_s.pluralize if ActiveRecord::Base.pluralize_table_names
          @base.add_foreign_key(@name, to_table, options)
        end

        def remove_foreign_key(options = {})
          ActiveSupport::Deprecation.warn "`remove_foreign_key` option will be deprecated. Please use `remove_references` option"
          @base.remove_foreign_key(@name, options)
        end
      end

    end
  end
end
