module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter < AbstractAdapter
      class SchemaCreation < AbstractAdapter::SchemaCreation
        private

        def visit_ColumnDefinition(o)
          if o.type.to_sym == :virtual
            sql_type = type_to_sql(o.default[:type], o.limit, o.precision, o.scale) if o.default[:type]
            "#{quote_column_name(o.name)} #{sql_type} AS (#{o.default[:as]})"
          else
            super
          end
        end

        def visit_TableDefinition(o)
          tablespace = tablespace_for(:table, o.options[:tablespace])
          create_sql = "CREATE#{' GLOBAL TEMPORARY' if o.temporary} TABLE "
          create_sql << "#{quote_table_name(o.name)} ("
          create_sql << o.columns.map { |c| accept c }.join(', ')
          create_sql << ")"
          unless o.temporary
            create_sql << " ORGANIZATION #{o.options[:organization]}" if o.options[:organization]
            create_sql << "#{tablespace}"
          end
          create_sql << " #{o.options[:options]}"
          create_sql
        end

        def tablespace_for(obj_type, tablespace_option, table_name=nil, column_name=nil)
          tablespace_sql = ''
          if tablespace = (tablespace_option || default_tablespace_for(obj_type))
            tablespace_sql << if [:blob, :clob].include?(obj_type.to_sym)
              " LOB (#{quote_column_name(column_name)}) STORE AS #{column_name.to_s[0..10]}_#{table_name.to_s[0..14]}_ls (TABLESPACE #{tablespace})"
            else
              " TABLESPACE #{tablespace}"
            end
          end
          tablespace_sql
        end

        def default_tablespace_for(type)
          (ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[type] || 
           ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[native_database_types[type][:name]]) rescue nil
        end

        def foreign_key_definition(to_table, options = {})
          @conn.foreign_key_definition(to_table, options)
        end

        def add_column_options!(sql, options)
          type = options[:type] || ((column = options[:column]) && column.type)
          type = type && type.to_sym
          # handle case of defaults for CLOB columns, which would otherwise get "quoted" incorrectly
          if options_include_default?(options)
            if type == :text
              sql << " DEFAULT #{@conn.quote(options[:default])}"
            else
              # from abstract adapter
              sql << " DEFAULT #{@conn.quote(options[:default], options[:column])}"
            end
          end
          # must explicitly add NULL or NOT NULL to allow change_column to work on migrations
          if options[:null] == false
            sql << " NOT NULL"
          elsif options[:null] == true
            sql << " NULL" unless type == :primary_key
          end
          # add AS expression for virtual columns
          if options[:as].present?
            sql << " AS (#{options[:as]})"
          end
        end

        # This method does not exist in SchemaCreation at Rails 4.0
        # It can be removed only when Oracle enhanced adapter supports Rails 4.1 and higher
        def options_include_default?(options)
          options.include?(:default) && !(options[:null] == false && options[:default].nil?)
        end

      end
      
      def schema_creation
          SchemaCreation.new self
      end

    end
  end
end
