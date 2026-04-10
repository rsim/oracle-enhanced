# frozen_string_literal: true

module ActiveRecord # :nodoc:
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced # :nodoc:
      module StructureDump # :nodoc:
        # Statements separator used in structure dump to allow loading of structure dump also with SQL*Plus
        STATEMENT_TOKEN = "\n\n/\n\n"

        def structure_dump # :nodoc:
          configure_dbms_metadata_transforms
          structure = []

          # Sequences
          sequence_names = select_values(<<~SQL.squish, "SCHEMA")
            SELECT sequence_name FROM all_sequences
            WHERE sequence_owner = SYS_CONTEXT('userenv', 'current_schema')
            ORDER BY 1
          SQL
          sequence_names.each do |seq_name|
            ddl = dbms_metadata_get_ddl("SEQUENCE", seq_name)
            structure << ddl if ddl
          end

          # Tables (excluding materialized views and their logs)
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
            ddl = dbms_metadata_get_ddl("TABLE", table_name)
            structure << ddl if ddl

            # Indexes — use the adapter's indexes() method to get non-constraint indexes,
            # then fetch DDL for each. GET_DEPENDENT_DDL('INDEX') includes constraint-backing
            # indexes (PK/UK) which cause ORA-01408 on structure_load.
            indexes(table_name).each do |idx|
              idx_ddl = dbms_metadata_get_ddl("INDEX", idx.name)
              structure << idx_ddl if idx_ddl
            end

            # Comments (table and column)
            comment_ddl = dbms_metadata_get_dependent_ddl("COMMENT", table_name)
            structure.concat(split_dbms_metadata_ddl(comment_ddl)) if comment_ddl
          end

          # Foreign key constraints (after all tables are created)
          fk_statements = []
          tables.each do |table_name|
            fk_ddl = dbms_metadata_get_dependent_ddl("REF_CONSTRAINT", table_name)
            fk_statements.concat(split_dbms_metadata_ddl(fk_ddl)) if fk_ddl
          end

          # Views
          view_names = select_values(<<~SQL.squish, "SCHEMA")
            SELECT view_name FROM all_views
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
            ORDER BY view_name ASC
          SQL
          view_names.each do |view_name|
            ddl = dbms_metadata_get_ddl("VIEW", view_name)
            structure << ddl if ddl
          end

          join_with_statement_token(structure) <<
            join_with_statement_token(fk_statements)
        ensure
          reset_dbms_metadata_transforms
        end

        # Extract all stored procedures, packages, synonyms.
        def structure_dump_db_stored_code # :nodoc:
          configure_dbms_metadata_transforms
          structure = []

          all_source = select_all(<<~SQL.squish, "SCHEMA")
            SELECT DISTINCT name, type
            FROM all_source
            WHERE type IN ('PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'TRIGGER', 'TYPE')
            AND name NOT LIKE 'BIN$%'
            AND owner = SYS_CONTEXT('userenv', 'current_schema') ORDER BY type
          SQL
          all_source.each do |source|
            # DBMS_METADATA uses 'PACKAGE_BODY' (underscore) not 'PACKAGE BODY' (space)
            metadata_type = source["type"].tr(" ", "_")
            ddl = dbms_metadata_get_ddl(metadata_type, source["name"])
            structure << ddl if ddl
          end

          # export synonyms
          structure << structure_dump_synonyms

          join_with_statement_token(structure)
        ensure
          reset_dbms_metadata_transforms
        end

        def structure_dump_synonyms # :nodoc:
          configure_dbms_metadata_transforms
          structure = []
          synonym_names = select_values(<<~SQL.squish, "SCHEMA")
            SELECT synonym_name FROM all_synonyms
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
          synonym_names.each do |synonym_name|
            ddl = dbms_metadata_get_ddl("SYNONYM", synonym_name)
            structure << ddl if ddl
          end
          join_with_statement_token(structure)
        ensure
          reset_dbms_metadata_transforms
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
        def configure_dbms_metadata_transforms
          execute(<<~SQL)
            BEGIN
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'TABLESPACE', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'EMIT_SCHEMA', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS', TRUE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS_AS_ALTER', FALSE);
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
            END;
          SQL
        end

        def reset_dbms_metadata_transforms
          execute(<<~SQL)
            BEGIN
              DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'DEFAULT');
            END;
          SQL
        end

        def dbms_metadata_get_ddl(object_type, object_name)
          result = select_value(
            "SELECT DBMS_METADATA.GET_DDL(#{quote(object_type)}, #{quote(object_name)}) FROM DUAL",
            "SCHEMA"
          )
          clean_dbms_metadata_ddl(result)
        end

        def dbms_metadata_get_dependent_ddl(dependent_type, base_object_name)
          result = select_value(
            "SELECT DBMS_METADATA.GET_DEPENDENT_DDL(#{quote(dependent_type)}, #{quote(base_object_name)}) FROM DUAL",
            "SCHEMA"
          )
          clean_dbms_metadata_ddl(result)
        rescue ActiveRecord::StatementInvalid => e
          raise unless e.message.include?("ORA-31608")
          nil
        end

        def clean_dbms_metadata_ddl(ddl)
          return nil if ddl.nil?
          result = ddl.to_s.strip
          result.empty? ? nil : result
        end

        # DBMS_METADATA.GET_DEPENDENT_DDL can return multiple DDL statements
        # concatenated in a single CLOB. Split them into individual statements.
        def split_dbms_metadata_ddl(ddl)
          return [] if ddl.nil?
          # Dependent DDL statements are typically separated by newlines.
          # Split on blank-line boundaries and filter empties.
          ddl.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
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
