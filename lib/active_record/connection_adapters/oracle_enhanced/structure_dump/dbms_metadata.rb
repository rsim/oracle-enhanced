# frozen_string_literal: true

require "active_record/connection_adapters/oracle_enhanced/structure_dump"

module ActiveRecord # :nodoc:
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced # :nodoc:
      module StructureDump # :nodoc:
        module DbmsMetadata # :nodoc:
          STRUCTURE_OBJECT_TYPES = [
            "SEQUENCE",
            "TABLE",
            "INDEX",
            "VIEW"
          ].freeze

          STORED_CODE_OBJECT_TYPES = [
            "FUNCTION",
            "PROCEDURE",
            "PACKAGE",
            "TYPE",
            "TRIGGER"
          ].freeze

          private_constant :STRUCTURE_OBJECT_TYPES, :STORED_CODE_OBJECT_TYPES

          private
            def dbms_metadata_structure_dump
              dbms_metadata_with_transforms(sql_terminator: true) do
                structure = []
                table_names = list_schema_objects("TABLE", non_mview_only: true)
                skip_indexes = constraint_backed_index_names
                invisible_indexes = invisible_index_names

                STRUCTURE_OBJECT_TYPES.each do |object_type|
                  names = if object_type == "TABLE"
                    table_names
                  else
                    list_schema_objects(object_type)
                  end
                  names.each do |name|
                    next if object_type == "INDEX" && skip_indexes.include?(name.upcase)
                    ddl = dbms_metadata_get_ddl(object_type.tr(" ", "_"), name)
                    next unless ddl
                    statements = split_dbms_metadata_sql_ddl(ddl)
                    if object_type == "INDEX" && invisible_indexes.include?(name.upcase)
                      statements = statements.map { |stmt| ensure_invisible_keyword(stmt) }
                    end
                    structure.concat(statements)
                  end
                end

                # Constraint-backed indexes (PRIMARY KEY / UNIQUE) are
                # inlined into the CREATE TABLE DDL by CONSTRAINTS=TRUE,
                # so they are skipped above and never receive the standalone
                # `INVISIBLE` patch via `ensure_invisible_keyword`. Restore
                # their visibility separately with an explicit
                # `ALTER INDEX ... INVISIBLE` after the table has been
                # created.
                (skip_indexes & invisible_indexes).sort.each do |index_name|
                  structure << "ALTER INDEX #{quote_column_name(index_name)} INVISIBLE"
                end

                table_names.each do |table_name|
                  structure.concat(dbms_metadata_structure_dump_table_comments(table_name))
                  structure.concat(dbms_metadata_structure_dump_column_comments(table_name))
                end

                fk_statements = table_names.flat_map do |table_name|
                  fk_ddl = dbms_metadata_get_dependent_ddl("REF_CONSTRAINT", table_name)
                  fk_ddl ? split_dbms_metadata_sql_ddl(fk_ddl) : []
                end

                join_with_statement_token(structure) << join_with_statement_token(fk_statements)
              end
            end

            def dbms_metadata_structure_dump_db_stored_code
              dbms_metadata_with_transforms do
                structure = STORED_CODE_OBJECT_TYPES.flat_map do |object_type|
                  list_schema_objects(object_type).filter_map do |name|
                    dbms_metadata_get_ddl(object_type, name)
                  end
                end
                structure << dbms_metadata_structure_dump_synonyms
                join_with_statement_token(structure)
              end
            end

            def dbms_metadata_structure_dump_synonyms
              dbms_metadata_with_transforms do
                structure = list_schema_objects("SYNONYM").filter_map do |synonym_name|
                  dbms_metadata_get_ddl("SYNONYM", synonym_name)
                end
                join_with_statement_token(structure)
              end
            end

            def dbms_metadata_with_transforms(sql_terminator: false)
              configure_dbms_metadata_transforms(sql_terminator: sql_terminator)
              yield
            ensure
              reset_dbms_metadata_transforms
            end

            def list_schema_objects(object_type, non_mview_only: false)
              binds = [bind_string("object_type", object_type)]
              # MV / MV log surface as TABLE in all_objects.
              mview_filter = if non_mview_only
                <<~SQL.squish
                  AND NOT EXISTS (SELECT 1 FROM all_mviews mv
                                  WHERE mv.owner = o.owner AND mv.mview_name = o.object_name)
                  AND NOT EXISTS (SELECT 1 FROM all_mview_logs mvl
                                  WHERE mvl.log_owner = o.owner AND mvl.log_table = o.object_name)
                SQL
              else
                ""
              end
              select_values(<<~SQL.squish, "SCHEMA", binds)
                SELECT object_name FROM all_objects o
                WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
                AND object_type = :object_type
                AND object_name NOT LIKE 'BIN$%'
                #{mview_filter}
                ORDER BY object_name
              SQL
            end

            # PRIMARY KEY / UNIQUE constraint backing indexes are already inlined by CONSTRAINTS=TRUE.
            def constraint_backed_index_names
              select_values(<<~SQL.squish, "SCHEMA").map(&:upcase).to_set
                SELECT index_name FROM all_constraints
                WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
                AND constraint_type IN ('P', 'U')
                AND index_name IS NOT NULL
              SQL
            end

            # SEGMENT_ATTRIBUTES=FALSE strips the storage clause from
            # GET_DDL output, and Oracle emits the INVISIBLE keyword
            # inside that same clause. Re-attach it from all_indexes so
            # invisible indexes round-trip on the DBMS_METADATA path.
            # Pre-11g has no invisible-index concept (and no `visibility`
            # column on `all_indexes`), so return an empty set there.
            def invisible_index_names
              return Set.new unless supports_disabling_indexes?
              select_values(<<~SQL.squish, "SCHEMA").map(&:upcase).to_set
                SELECT index_name FROM all_indexes
                WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
                AND visibility = 'INVISIBLE'
              SQL
            end

            def ensure_invisible_keyword(ddl)
              return ddl if ddl.match?(/\bINVISIBLE\b/i)
              "#{ddl.rstrip} INVISIBLE"
            end

            # GET_DEPENDENT_DDL("COMMENT", ...) returns an empty CLOB; query directly.
            def dbms_metadata_structure_dump_table_comments(table_name)
              comment = table_comment(table_name)
              return [] if comment.nil?
              ["COMMENT ON TABLE #{quote_table_name(table_name)} IS '#{quote_string(comment)}'"]
            end

            def dbms_metadata_structure_dump_column_comments(table_name)
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
              comments
            end

            # Suppress installation-specific output, in spirit of
            # `pg_dump --schema-only --no-owner --no-tablespaces`.
            # When `sql_terminator: true` is requested, also tell Oracle
            # to append a SQL terminator (`;`) to each statement so the
            # caller can split a multi-statement TABLE DDL CLOB on the
            # boundary; this is only safe for the SQL DDL path (TABLE /
            # SEQUENCE / VIEW / INDEX). The PL/SQL DDL path leaves
            # SQLTERMINATOR at the default FALSE because PL/SQL bodies
            # contain `;` characters internally (`END;`).
            def configure_dbms_metadata_transforms(sql_terminator: false)
              execute(<<~SQL)
                BEGIN
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'TABLESPACE', FALSE);
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'EMIT_SCHEMA', FALSE);
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', FALSE);
                  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', #{sql_terminator ? "TRUE" : "FALSE"});
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
              binds = [
                bind_string("object_type", object_type),
                bind_string("object_name", object_name)
              ]
              result = select_value(
                "SELECT DBMS_METADATA.GET_DDL(:object_type, :object_name) FROM DUAL",
                "SCHEMA",
                binds
              )
              clean_dbms_metadata_ddl(result)
            rescue ActiveRecord::StatementInvalid => e
              # ORA-31603: object not found (race vs another session dropping
              # the object between the ALL_OBJECTS scan and GET_DDL).
              raise unless e.message.include?("ORA-31603")
              nil
            end

            def dbms_metadata_get_dependent_ddl(dependent_type, base_object_name)
              binds = [
                bind_string("dependent_type", dependent_type),
                bind_string("base_object_name", base_object_name)
              ]
              result = select_value(
                "SELECT DBMS_METADATA.GET_DEPENDENT_DDL(:dependent_type, :base_object_name) FROM DUAL",
                "SCHEMA",
                binds
              )
              clean_dbms_metadata_ddl(result)
            rescue ActiveRecord::StatementInvalid => e
              # ORA-31608: dependent object not found (e.g. no triggers / no FKs).
              raise unless e.message.include?("ORA-31608")
              nil
            end

            def clean_dbms_metadata_ddl(ddl)
              return nil if ddl.nil?
              result = ddl.to_s.strip
              result.empty? ? nil : result
            end

            # GET_DEPENDENT_DDL can return multiple DDL statements concatenated
            # in a single CLOB. Split on blank-line boundaries.
            def split_dbms_metadata_ddl(ddl)
              return [] if ddl.nil?
              ddl.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
            end

            # `GET_DDL('TABLE', t)` can return more than one SQL statement
            # in a single CLOB when the table has a UNIQUE constraint
            # backed by a separately-named index (Oracle emits the
            # `CREATE TABLE`, the `CREATE UNIQUE INDEX`, and the
            # `ALTER TABLE ... ADD CONSTRAINT ... USING INDEX ...` as a
            # group). With `SQLTERMINATOR=TRUE` each statement ends in
            # `;`, so split on the terminator to surface each statement
            # to the structure-dump output as its own entry.
            def split_dbms_metadata_sql_ddl(ddl)
              return [] if ddl.nil?
              ddl.split(/;\s*(?:\n|\z)/).map(&:strip).reject(&:empty?)
            end
        end
      end
    end
  end
end
