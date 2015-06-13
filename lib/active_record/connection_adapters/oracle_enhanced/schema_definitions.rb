module ActiveRecord
  module ConnectionAdapters
    #TODO: Overriding `aliased_types` cause another database adapter behavior changes
    #It should be addressed by supporting `create_table_definition`
    class TableDefinition
      private
      def aliased_types(name, fallback)
        fallback
      end
    end

    class OracleEnhancedForeignKeyDefinition < ForeignKeyDefinition
    end


    module OracleEnhanced
    
      class SynonymDefinition < Struct.new(:name, :table_owner, :table_name, :db_link) #:nodoc:
      end

      class IndexDefinition < ActiveRecord::ConnectionAdapters::IndexDefinition
        attr_accessor :table, :name, :unique, :type, :parameters, :statement_parameters, :tablespace, :columns
  
        def initialize(table, name, unique, type, parameters, statement_parameters, tablespace, columns)
          @table = table
          @name = name
          @unique = unique
          @type = type
          @parameters = parameters
          @statement_parameters = statement_parameters
          @tablespace = tablespace
          @columns = columns
          super(table, name, unique, columns, nil, nil, nil, nil)
        end
      end
    end

    module OracleEnhancedSchemaDefinitions #:nodoc:
      def self.included(base)
        base::TableDefinition.class_eval do
          include OracleEnhancedTableDefinition
        end

        # Available starting from ActiveRecord 2.1
        base::Table.class_eval do
          include OracleEnhancedTable
        end if defined?(base::Table)
      end
    end
  
    module OracleEnhancedTableDefinition
      class ForeignKey < Struct.new(:base, :to_table, :options) #:nodoc:
        def to_sql
          base.foreign_key_definition(to_table, options)
        end
        alias to_s :to_sql
      end

      def self.included(base) #:nodoc:
        base.class_eval do
          alias_method_chain :column, :virtual_columns
        end
      end

      def raw(name, options={})
        column(name, :raw, options)
      end

      def virtual(* args)
        options = args.extract_options!
        column_names = args
        column_names.each { |name| column(name, :virtual, options) }
      end

      def column_with_virtual_columns(name, type, options = {})
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
        column_without_virtual_columns(name, type, options)
      end
    
      # Adds a :foreign_key option to TableDefinition.references.
      # If :foreign_key is true, a foreign key constraint is added to the table.
      # You can also specify a hash, which is passed as foreign key options.
      # 
      # ===== Examples
      # ====== Add goat_id column and a foreign key to the goats table.
      #  t.references(:goat, :foreign_key => true)
      # ====== Add goat_id column and a cascading foreign key to the goats table.
      #  t.references(:goat, :foreign_key => {:dependent => :delete})
      # 
      # Note: No foreign key is created if :polymorphic => true is used.
      # Note: If no name is specified, the database driver creates one for you!
      def references(*args)
        options = args.extract_options!
        index_options = options[:index]
        fk_options = options.delete(:foreign_key)

        if fk_options && !options[:polymorphic]
          fk_options = {} if fk_options == true
          args.each do |to_table| 
            foreign_key(to_table, fk_options) 
            add_index(to_table, "#{to_table}_id", index_options.is_a?(Hash) ? index_options : nil) if index_options
          end
        end

        super(*(args << options))
      end
  
      # Defines a foreign key for the table. +to_table+ can be a single Symbol, or
      # an Array of Symbols. See SchemaStatements#add_foreign_key
      #
      # ===== Examples
      # ====== Creating a simple foreign key
      #  t.foreign_key(:people)
      # ====== Defining the column
      #  t.foreign_key(:people, :column => :sender_id)
      # ====== Creating a named foreign key
      #  t.foreign_key(:people, :column => :sender_id, :name => 'sender_foreign_key')
      # ====== Defining the column of the +to_table+.
      #  t.foreign_key(:people, :column => :sender_id, :primary_key => :person_id)
      def foreign_key(to_table, options = {})
        #TODO
        if ActiveRecord::Base.connection.supports_foreign_keys?
          to_table = to_table.to_s.pluralize if ActiveRecord::Base.pluralize_table_names
          foreign_keys << ForeignKey.new(@base, to_table, options)
        else
          raise ArgumentError, "this ActiveRecord adapter is not supporting foreign_key definition"
        end
      end
    
      def foreign_keys
        @foreign_keys ||= []
      end
    end

    module OracleEnhancedTable

      # Adds a new foreign key to the table. +to_table+ can be a single Symbol, or
      # an Array of Symbols. See SchemaStatements#add_foreign_key
      #
      # ===== Examples
      # ====== Creating a simple foreign key
      #  t.foreign_key(:people)
      # ====== Defining the column
      #  t.foreign_key(:people, :column => :sender_id)
      # ====== Creating a named foreign key
      #  t.foreign_key(:people, :column => :sender_id, :name => 'sender_foreign_key')
      # ====== Defining the column of the +to_table+.
      #  t.foreign_key(:people, :column => :sender_id, :primary_key => :person_id)
      def foreign_key(to_table, options = {})
        if @base.respond_to?(:supports_foreign_keys?) && @base.supports_foreign_keys?
          to_table = to_table.to_s.pluralize if ActiveRecord::Base.pluralize_table_names
          @base.add_foreign_key(@table_name, to_table, options)
        else
          raise ArgumentError, "this ActiveRecord adapter is not supporting foreign_key definition"
        end
      end
  
      # Remove the given foreign key from the table.
      #
      # ===== Examples
      # ====== Remove the suppliers_company_id_fk in the suppliers table.
      #   t.remove_foreign_key :companies
      # ====== Remove the foreign key named accounts_branch_id_fk in the accounts table.
      #   remove_foreign_key :column => :branch_id
      # ====== Remove the foreign key named party_foreign_key in the accounts table.
      #   remove_index :name => :party_foreign_key
      def remove_foreign_key(options = {})
        @base.remove_foreign_key(@table_name, options)
      end
    
      # Adds a :foreign_key option to TableDefinition.references.
      # If :foreign_key is true, a foreign key constraint is added to the table.
      # You can also specify a hash, which is passed as foreign key options.
      # 
      # ===== Examples
      # ====== Add goat_id column and a foreign key to the goats table.
      #  t.references(:goat, :foreign_key => true)
      # ====== Add goat_id column and a cascading foreign key to the goats table.
      #  t.references(:goat, :foreign_key => {:dependent => :delete})
      # 
      # Note: No foreign key is created if :polymorphic => true is used.
      def references(*args)
        options = args.extract_options!
        polymorphic = options[:polymorphic]
        index_options = options[:index]
        fk_options = options.delete(:foreign_key)

        super(*(args << options))
        # references_without_foreign_keys adds {:type => :integer}
        args.extract_options!
        if fk_options && !polymorphic
          fk_options = {} if fk_options == true
          args.each do |to_table| 
            foreign_key(to_table, fk_options) 
            add_index(to_table, "#{to_table}_id", index_options.is_a?(Hash) ? index_options : nil) if index_options
          end
        end
      end
    end
  end
end

ActiveRecord::ConnectionAdapters.class_eval do
  include ActiveRecord::ConnectionAdapters::OracleEnhancedSchemaDefinitions
end
