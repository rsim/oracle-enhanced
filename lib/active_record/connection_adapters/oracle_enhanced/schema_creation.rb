module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      class SchemaCreation < AbstractAdapter::SchemaCreation
        private

        def visit_ColumnDefinition(o)
          case
            when o.type.to_sym == :virtual
              sql_type = type_to_sql(o.default[:type], o.limit, o.precision, o.scale) if o.default[:type]
              return "#{quote_column_name(o.name)} #{sql_type} AS (#{o.default[:as]})"
            when [:blob, :clob].include?(sql_type = type_to_sql(o.type.to_sym,  o.limit, o.precision, o.scale).downcase.to_sym)
              if (tablespace = default_tablespace_for(sql_type))
                @lob_tablespaces ||= {}
                @lob_tablespaces[o.name] = tablespace
              end
          end
          super
        end

        def visit_TableDefinition(o)
          create_sql = "CREATE#{' GLOBAL TEMPORARY' if o.temporary} TABLE #{quote_table_name(o.name)} "
          statements = o.columns.map { |c| accept c }
          statements << accept(o.primary_keys) if o.primary_keys

          if supports_foreign_keys?
            statements.concat(o.foreign_keys.map { |to_table, options| foreign_key_in_create(o.name, to_table, options) })
          end

          create_sql << "(#{statements.join(', ')})" if statements.present?

          unless o.temporary
            @lob_tablespaces.each do |lob_column, tablespace|
              create_sql << " LOB (#{quote_column_name(lob_column)}) STORE AS (TABLESPACE #{tablespace}) \n"
            end if defined?(@lob_tablespaces)
            create_sql << " ORGANIZATION #{o.organization}" if o.organization
            if (tablespace = o.tablespace || default_tablespace_for(:table))
              create_sql << " TABLESPACE #{tablespace}"
            end
          end
          add_table_options!(create_sql, table_options(o))
          create_sql << " AS #{@conn.to_sql(o.as)}" if o.as
          create_sql
        end

        def default_tablespace_for(type)
          (ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[type] || 
           ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[native_database_types[type][:name]]) rescue nil
        end

        def add_column_options!(sql, options)
          type = options[:type] || ((column = options[:column]) && column.type)
          type = type && type.to_sym
          # handle case of defaults for CLOB columns, which would otherwise get "quoted" incorrectly
          if options_include_default?(options)
            if type == :text
              sql << " DEFAULT #{@conn.quote(options[:default])}"
            else
              sql << " DEFAULT #{quote_default_expression(options[:default], options[:column])}"
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
          if options[:primary_key] == true
            sql << " PRIMARY KEY"
          end
        end

        def action_sql(action, dependency)
          if action == 'UPDATE'
            raise ArgumentError, <<-MSG.strip_heredoc
              '#{action}' is not supported by Oracle
            MSG
          end
          case dependency
          when :nullify then "ON #{action} SET NULL"
          when :cascade  then "ON #{action} CASCADE"
          else
            raise ArgumentError, <<-MSG.strip_heredoc
              '#{dependency}' is not supported for #{action}
              Supported values are: :nullify, :cascade
            MSG
          end
        end

      end
    end
  end
end
