# frozen_string_literal: true

module ActiveRecord # :nodoc:
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced # :nodoc:
      module StructureDump # :nodoc:
        # Statements separator used in structure dump to allow loading of structure dump also with SQL*Plus
        STATEMENT_TOKEN = "\n\n/\n\n"

        def structure_dump # :nodoc:
          sequences = select(<<~SQL.squish, "SCHEMA")
            SELECT
            sequence_name, min_value, max_value, increment_by, order_flag, cycle_flag
            FROM all_sequences
            where sequence_owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY 1
          SQL

          structure = sequences.map do |result|
            "CREATE SEQUENCE #{quote_table_name(result["sequence_name"])} MINVALUE #{result["min_value"]} MAXVALUE #{result["max_value"]} INCREMENT BY #{result["increment_by"]} #{result["order_flag"] == 'Y' ? "ORDER" : "NOORDER"} #{result["cycle_flag"] == 'Y' ? "CYCLE" : "NOCYCLE"}"
          end
          tables = select_values(<<~SQL.squish, "SCHEMA")
            SELECT table_name FROM all_tables t
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema') AND secondary = 'N'
            AND NOT EXISTS (SELECT mv.mview_name FROM all_mviews mv
                            WHERE mv.owner = t.owner AND mv.mview_name = t.table_name)
            AND NOT EXISTS (SELECT mvl.log_table FROM all_mview_logs mvl
                            WHERE mvl.log_owner = t.owner AND mvl.log_table = t.table_name)
            ORDER BY 1
          SQL
          tables.each do |table_name|
            virtual_columns = virtual_columns_for(table_name) if supports_virtual_columns?
            ddl = +"CREATE#{ ' GLOBAL TEMPORARY' if temporary_table?(table_name)} TABLE \"#{table_name}\" (\n"
            columns = select_all(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name)])
              SELECT column_name, data_type, data_length, char_used, char_length,
              data_precision, data_scale, data_default, nullable
              FROM all_tab_columns
              WHERE table_name = :table_name
              AND owner = SYS_CONTEXT('userenv', 'current_schema')
              ORDER BY column_id
            SQL
            cols = columns.map do |row|
              if (v = virtual_columns.find { |col| col["column_name"] == row["column_name"] })
                structure_dump_virtual_column(row, v["data_default"])
              else
                structure_dump_column(row)
              end
            end
            ddl << cols.map { |col| " #{col}" }.join(",\n")
            ddl << structure_dump_primary_key(table_name)
            ddl << "\n)"
            structure << ddl
            structure << structure_dump_indexes(table_name)
            structure << structure_dump_unique_keys(table_name)
            structure << structure_dump_table_comments(table_name)
            structure << structure_dump_column_comments(table_name)
          end

          join_with_statement_token(structure) <<
            structure_dump_fk_constraints <<
            structure_dump_views
        end

        def structure_dump_column(column) # :nodoc:
          col = +"\"#{column['column_name']}\" #{column['data_type']}"
          if (column["data_type"] == "NUMBER") && !column["data_precision"].nil?
            col << "(#{column['data_precision'].to_i}"
            col << ",#{column['data_scale'].to_i}" if !column["data_scale"].nil?
            col << ")"
          elsif column["data_type"].include?("CHAR") || column["data_type"] == "RAW"
            length = column["char_used"] == "C" ? column["char_length"].to_i : column["data_length"].to_i
            col << "(#{length})"
          end
          col << " DEFAULT #{column['data_default']}" if !column["data_default"].nil?
          col << " NOT NULL" if column["nullable"] == "N"
          col
        end

        def structure_dump_virtual_column(column, data_default) # :nodoc:
          data_default = data_default.delete('"')
          col = +"\"#{column['column_name']}\" #{column['data_type']}"
          if (column["data_type"] == "NUMBER") && !column["data_precision"].nil?
            col << "(#{column['data_precision'].to_i}"
            col << ",#{column['data_scale'].to_i}" if !column["data_scale"].nil?
            col << ")"
          elsif column["data_type"].include?("CHAR") || column["data_type"] == "RAW"
            length = column["char_used"] == "C" ? column["char_length"].to_i : column["data_length"].to_i
            col << "(#{length})"
          end
          col << " GENERATED ALWAYS AS (#{data_default}) VIRTUAL"
        end

        def structure_dump_primary_key(table) # :nodoc:
          opts = { name: "", cols: [] }
          pks = select_all(<<~SQL.squish, "SCHEMA")
            SELECT a.constraint_name, a.column_name, a.position
              FROM all_cons_columns a
              JOIN all_constraints c
                ON a.constraint_name = c.constraint_name
             WHERE c.table_name = '#{table.upcase}'
               AND c.constraint_type = 'P'
               AND a.owner = c.owner
               AND c.owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          pks.each do |row|
            opts[:name] = row["constraint_name"]
            opts[:cols][row["position"] - 1] = row["column_name"]
          end
          opts[:cols].length > 0 ? ",\n CONSTRAINT #{opts[:name]} PRIMARY KEY (#{opts[:cols].join(',')})" : ""
        end

        def structure_dump_unique_keys(table) # :nodoc:
          keys = {}
          uks = select_all(<<~SQL.squish, "SCHEMA")
            SELECT a.constraint_name, a.column_name, a.position
              FROM all_cons_columns a
              JOIN all_constraints c
                ON a.constraint_name = c.constraint_name
             WHERE c.table_name = '#{table.upcase}'
               AND c.constraint_type = 'U'
               AND a.owner = c.owner
               AND c.owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          uks.each do |uk|
            keys[uk["constraint_name"]] ||= []
            keys[uk["constraint_name"]][uk["position"] - 1] = uk["column_name"]
          end
          keys.map do |k, v|
            "ALTER TABLE #{table.upcase} ADD CONSTRAINT #{k} UNIQUE (#{v.join(',')})"
          end
        end

        def structure_dump_indexes(table_name) # :nodoc:
          indexes(table_name).map do |options|
            column_names = options.columns
            options = { name: options.name, unique: options.unique }
            index_name = index_name(table_name, column: column_names)
            if Hash === options # legacy support, since this param was a string
              index_type = options[:unique] ? "UNIQUE" : ""
              index_name = options[:name] || index_name
            else
              index_type = options
            end
            quoted_column_names = column_names.map { |e| quote_column_name_or_expression(e) }.join(", ")
            "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{quoted_column_names})"
          end
        end

        def structure_dump_fk_constraints # :nodoc:
          foreign_keys = select_all(<<~SQL.squish, "SCHEMA")
            SELECT table_name FROM all_tables
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY 1
          SQL
          fks = foreign_keys.map do |table|
            if respond_to?(:foreign_keys) && (foreign_keys = foreign_keys(table["table_name"])).any?
              foreign_keys.map do |fk|
                sql = +"ALTER TABLE #{quote_table_name(fk.from_table)} ADD CONSTRAINT #{quote_column_name(fk.options[:name])} "
                sql << "#{foreign_key_definition(fk.to_table, fk.options)}"
              end
            end
          end.flatten.compact
          join_with_statement_token(fks)
        end

        def structure_dump_table_comments(table_name)
          comments = []
          comment = table_comment(table_name)

          unless comment.nil?
            comments << "COMMENT ON TABLE #{quote_table_name(table_name)} IS '#{quote_string(comment)}'"
          end

          join_with_statement_token(comments)
        end

        def structure_dump_column_comments(table_name)
          comments = []
          columns = select_values(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name)])
            SELECT column_name FROM all_tab_columns
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
            AND table_name = :table_name ORDER BY column_id
          SQL

          columns.each do |column|
            comment = column_comment(table_name, column)
            unless comment.nil?
              comments << "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column)} IS '#{quote_string(comment)}'"
            end
          end

          join_with_statement_token(comments)
        end

        def foreign_key_definition(to_table, options = {}) # :nodoc:
          column_sql = quote_column_name(options[:column] || "#{to_table.to_s.singularize}_id")
          references = options[:references] ? options[:references].first : nil
          references_sql = quote_column_name(options[:primary_key] || references || "id")

          sql = "FOREIGN KEY (#{column_sql}) REFERENCES #{quote_table_name(to_table)}(#{references_sql})"

          case options[:dependent]
          when :nullify
            sql << " ON DELETE SET NULL"
          when :delete
            sql << " ON DELETE CASCADE"
          end
          sql
        end

        # Extract all stored procedures, packages, synonyms.
        def structure_dump_db_stored_code # :nodoc:
          structure = []
          all_source = select_all(<<~SQL.squish, "SCHEMA")
            SELECT DISTINCT name, type
            FROM all_source
            WHERE type IN ('PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'TRIGGER', 'TYPE')
            AND name NOT LIKE 'BIN$%'
            AND owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY type
          SQL
          all_source.each do |source|
            ddl = +"CREATE OR REPLACE   \n"
            texts = select_all(<<~SQL.squish, "all source at structure dump", [bind_string("source_name", source["name"]), bind_string("source_type", source["type"])])
              SELECT text
              FROM all_source
              WHERE name = :source_name
              AND type = :source_type
              AND owner = SYS_CONTEXT('userenv', 'current_schema')
              ORDER BY line
            SQL
            texts.each do |row|
              ddl << row["text"]
            end
            ddl << ";" unless ddl.strip[-1, 1] == ";"
            structure << ddl
          end

          # export synonyms
          structure << structure_dump_synonyms

          join_with_statement_token(structure)
        end

        def structure_dump_views # :nodoc:
          structure = []
          views = select_all(<<~SQL.squish, "SCHEMA")
            SELECT view_name, text FROM all_views
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY view_name ASC
          SQL
          views.each do |view|
            structure << "CREATE OR REPLACE FORCE VIEW #{view['view_name']} AS\n #{view['text']}"
          end
          join_with_statement_token(structure)
        end

        def structure_dump_synonyms # :nodoc:
          structure = []
          synonyms = select_all(<<~SQL.squish, "SCHEMA")
            SELECT owner, synonym_name, table_name, table_owner
            FROM all_synonyms
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          synonyms.each do |synonym|
            structure << "CREATE OR REPLACE #{synonym['owner'] == 'PUBLIC' ? 'PUBLIC' : '' } SYNONYM #{synonym['synonym_name']}
            FOR #{synonym['table_owner']}.#{synonym['table_name']}"
          end
          join_with_statement_token(structure)
        end

        def structure_drop # :nodoc:
          sequences = select_values(<<~SQL.squish, "SCHEMA")
            SELECT
            sequence_name FROM all_sequences where sequence_owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY 1
          SQL
          statements = sequences.map do |seq|
            "DROP SEQUENCE \"#{seq}\""
          end
          tables = select_values(<<~SQL.squish, "SCHEMA")
            SELECT table_name from all_tables t
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema') AND secondary = 'N'
            AND NOT EXISTS (SELECT mv.mview_name FROM all_mviews mv
                            WHERE mv.owner = t.owner AND mv.mview_name = t.table_name)
            AND NOT EXISTS (SELECT mvl.log_table FROM all_mview_logs mvl
                            WHERE mvl.log_owner = t.owner AND mvl.log_table = t.table_name)
            ORDER BY 1
          SQL
          tables.each do |table|
            statements << "DROP TABLE \"#{table}\" CASCADE CONSTRAINTS"
          end
          join_with_statement_token(statements)
        end

        def temp_table_drop # :nodoc:
          temporary_tables = select_values(<<~SQL.squish, "SCHEMA")
            SELECT table_name FROM all_tables
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
            AND secondary = 'N' AND temporary = 'Y' ORDER BY 1
          SQL
          statements = temporary_tables.map do |table|
            "DROP TABLE \"#{table}\" CASCADE CONSTRAINTS"
          end
          join_with_statement_token(statements)
        end

        def full_drop(preserve_tables = false) # :nodoc:
          s = preserve_tables ? [] : [structure_drop]
          s << temp_table_drop if preserve_tables
          s << drop_sql_for_feature("view")
          s << drop_sql_for_feature("materialized view")
          s << drop_sql_for_feature("synonym")
          s << drop_sql_for_feature("type")
          s << drop_sql_for_object("package")
          s << drop_sql_for_object("function")
          s << drop_sql_for_object("procedure")
          s.join
        end

        def execute_structure_dump(string)
          string.split(STATEMENT_TOKEN).each do |ddl|
            execute(ddl) unless ddl.blank?
          end
        end

      private
        # Called only if `supports_virtual_columns?` returns true
        # return [{'column_name' => 'FOOS', 'data_default' => '...'}, ...]
        def virtual_columns_for(table)
          select_all(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table.upcase)])
            SELECT column_name, data_default
            FROM all_tab_cols
            WHERE virtual_column = 'YES'
            AND owner = SYS_CONTEXT('userenv', 'current_schema')
            AND table_name = :table_name
          SQL
        end

        def drop_sql_for_feature(type)
          short_type = type == "materialized view" ? "mview" : type
          features = select_values(<<~SQL.squish, "SCHEMA")
            SELECT #{short_type}_name FROM all_#{short_type.tableize}
            where owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          statements = features.map do |name|
            "DROP #{type.upcase} \"#{name}\""
          end
          join_with_statement_token(statements)
        end

        def drop_sql_for_object(type)
          objects = select_values(<<~SQL.squish, "SCHEMA")
            SELECT object_name FROM all_objects
            WHERE object_type = '#{type.upcase}' and owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          statements = objects.map do |name|
            "DROP #{type.upcase} \"#{name}\""
          end
          join_with_statement_token(statements)
        end

        def join_with_statement_token(array)
          string = array.join(STATEMENT_TOKEN)
          string << STATEMENT_TOKEN unless string.blank?
          string
        end
      end
    end
  end
end
