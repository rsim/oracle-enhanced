# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      class SchemaCreation < SchemaCreation
        private
          def visit_ColumnDefinition(o)
            if [:blob, :clob, :nclob].include?(sql_type = type_to_sql(o.type, **o.options).downcase.to_sym)
              if (tablespace = default_tablespace_for(sql_type))
                @lob_tablespaces ||= {}
                @lob_tablespaces[o.name] = tablespace
              end
            end
            o.cast_type = lookup_cast_type(sql_type)
            if o.type == :primary_key && o.options[:identity]
              o.sql_type = type_to_sql(:identity_primary_key)
              return "#{quote_column_name(o.name)} #{o.sql_type}"
            end
            super
          end

          def visit_TableDefinition(o)
            create_sql = +"CREATE#{' GLOBAL TEMPORARY' if o.temporary} TABLE #{quote_table_name(o.name)} "
            statements = o.columns.map { |c| accept c }
            statements << accept(o.primary_keys) if o.primary_keys

            if use_foreign_keys?
              statements.concat(o.foreign_keys.map { |fk| accept fk })
            end

            if supports_unique_constraints? && o.respond_to?(:unique_constraints)
              statements.concat(o.unique_constraints.map { |uc| accept uc })
            end

            if supports_check_constraints? && o.respond_to?(:check_constraints)
              statements.concat(o.check_constraints.map { |chk| accept chk })
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
            add_table_options!(create_sql, o)
            create_sql << " AS #{to_sql(o.as)}" if o.as
            create_sql
          end

          def default_tablespace_for(type)
            OracleEnhancedAdapter.default_tablespaces[type]
          end

          def add_column_options!(sql, options)
            type = options[:type] || ((column = options[:column]) && column.type)
            type = type && type.to_sym
            # handle case of defaults for CLOB/NCLOB columns, which would otherwise get "quoted" incorrectly
            if options_include_default?(options)
              if type == :text
                sql << " DEFAULT #{@conn.quote(options[:default])}"
              elsif type == :ntext
                sql << " DEFAULT #{@conn.quote(options[:default])}"
              else
                sql << " DEFAULT #{quote_default_expression(options[:default], options[:column])}"
              end
            end
            # must explicitly add NULL or NOT NULL to allow change_column to work on migrations
            if options[:null] == false
              sql << " NOT NULL"
            elsif options[:null] == true
              sql << " NULL"
            end
            # add AS expression for virtual columns
            if options[:as].present?
              sql << " AS (#{options[:as]})"
            end
            if options[:primary_key] == true
              sql << " PRIMARY KEY"
            end
          end

          def visit_ForeignKeyDefinition(o)
            super.dup.tap do |sql|
              sql << " DEFERRABLE INITIALLY #{o.deferrable.to_s.upcase}" if o.deferrable
              sql << " NOVALIDATE" unless o.validate?
            end
          end

          def visit_AlterTable(o)
            sql = super
            sql << o.unique_constraint_adds.map { |c| visit_AddUniqueConstraint(c) }.join(" ")
            sql << o.constraint_validations.map { |name| visit_ValidateConstraint(name) }.join(" ")
          end

          def visit_CheckConstraintDefinition(o)
            super.dup.tap { |sql| sql << " NOVALIDATE" unless o.validate? }
          end

          def visit_ValidateConstraint(name)
            "MODIFY CONSTRAINT #{quote_column_name(name)} VALIDATE"
          end

          def visit_UniqueConstraintDefinition(o)
            cols = Array(o.column).map { |c| quote_column_name(c) }.join(", ")
            sql = ["CONSTRAINT", quote_column_name(o.name), "UNIQUE", "(#{cols})"]

            sql << "DEFERRABLE INITIALLY #{o.deferrable.to_s.upcase}" if o.deferrable
            sql << "USING INDEX #{quote_column_name(o.using_index)}" if o.using_index

            sql.join(" ")
          end

          def visit_AddUniqueConstraint(o)
            "ADD #{accept(o)}"
          end

          def visit_CreateIndexDefinition(o)
            index = o.index

            sql = ["CREATE"]
            sql << "UNIQUE" if index.unique
            sql << "INDEX"
            sql << quote_column_name(index.name)
            sql << "ON"
            sql << quote_table_name(index.table)
            sql << "(#{quoted_columns(index)})"
            sql << index.statement_parameters if index.statement_parameters.present?
            sql << "INVISIBLE" if index.respond_to?(:disabled?) && index.disabled?
            sql << "TABLESPACE #{index.tablespace}" if index.tablespace.present?

            sql.join(" ")
          end

          def action_sql(action, dependency)
            if action == "UPDATE"
              raise ArgumentError, <<~MSG
                '#{action}' is not supported by Oracle
              MSG
            end
            case dependency
            when :nullify then "ON #{action} SET NULL"
            when :cascade  then "ON #{action} CASCADE"
            else
              raise ArgumentError, <<~MSG
                '#{dependency}' is not supported for #{action}
                Supported values are: :nullify, :cascade
              MSG
            end
          end
      end
    end
  end
end
