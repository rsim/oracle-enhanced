# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseStatements
        # DATABASE STATEMENTS ======================================
        #
        # see: abstract/database_statements.rb

        READ_QUERY = ActiveRecord::ConnectionAdapters::AbstractAdapter.build_read_query_regexp(
          :close, :declare, :fetch, :move, :set, :show
        ) # :nodoc:
        private_constant :READ_QUERY

        def write_query?(sql) # :nodoc:
          !READ_QUERY.match?(sql)
        rescue ArgumentError # Invalid encoding
          !READ_QUERY.match?(sql.b)
        end

        # Add /*+ WITH_PLSQL */ hint for INSERT/UPDATE statements containing
        # PL/SQL function definitions. Oracle requires this hint for DML
        # statements that use PL/SQL in a WITH clause.
        def preprocess_query(sql)
          sql = super

          if sql =~ /\A\s*(INSERT|UPDATE)\b(?=.*\bBEGIN\b)/im
            sql = sql.sub($1, "#{$1} /*+ WITH_PLSQL */")
          end

          sql
        end

        # Executes a SQL statement
        def execute(...)
          super
        end

        # Low level execution of a SQL statement on the connection returning adapter specific result object.
        def raw_execute(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false, materialize_transactions: false)
          type_casted_binds = type_casted_binds(binds)
          with_raw_connection(allow_retry: allow_retry, materialize_transactions: materialize_transactions) do |conn|
            log(sql, name, binds, type_casted_binds, async: async) do
              cursor = nil
              cached = false
              with_retry do
                if binds.nil? || binds.empty?
                  cursor = conn.prepare(sql)
                else
                  unless @statements.key? sql
                    @statements[sql] = conn.prepare(sql)
                  end

                  cursor = @statements[sql]
                  cursor.bind_params(type_casted_binds)

                  cached = true
                end
                cursor.exec
              end

              columns = cursor.get_col_names.map do |col_name|
                oracle_downcase(col_name)
              end

              rows = []
              if cursor.select_statement?
                fetch_options = { get_lob_value: (name != "Writable Large Object") }
                while row = cursor.fetch(fetch_options)
                  rows << row
                end
              end

              affected_rows_count = cursor.row_count

              cursor.close unless cached

              { columns: columns, rows: rows, affected_rows_count: affected_rows_count }
            end
          end
        end

        def cast_result(result)
          if result.nil?
            ActiveRecord::Result.empty
          else
            ActiveRecord::Result.new(result[:columns], result[:rows])
          end
        end

        def affected_rows(result)
          result[:affected_rows_count]
        end

        def supports_explain?
          true
        end

        def explain(arel, binds = [], options = [])
          sql = "EXPLAIN PLAN FOR #{to_sql(arel, binds)}"
          return if /FROM all_/.match?(sql)
          if ORACLE_ENHANCED_CONNECTION == :jdbc
            exec_query(sql, "EXPLAIN", binds)
          else
            exec_query(sql, "EXPLAIN")
          end
          select_values("SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)", "EXPLAIN").join("\n")
        end

        def build_explain_clause(options = [])
          # Oracle does not have anything similar to "EXPLAIN ANALYZE"
          # https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/EXPLAIN-PLAN.html#GUID-FD540872-4ED3-4936-96A2-362539931BA0
        end

        # New method in ActiveRecord 3.1
        # Will add RETURNING clause in case of trigger generated primary keys
        def sql_for_insert(sql, pk, binds, _returning)
          unless pk == false || pk.nil? || pk.is_a?(Array) || pk.is_a?(String)
            sql = "#{sql} RETURNING #{quote_column_name(pk)} INTO :returning_id"
            (binds = binds.dup) << ActiveRecord::Relation::QueryAttribute.new("returning_id", nil, Type::OracleEnhanced::Integer.new)
          end
          super
        end

        def insert(arel, name = nil, pk = nil, id_value = nil, sequence_name = nil, binds = [], returning: nil)
          pk = nil if id_value
          Array(super || id_value)
        end

        # New method in ActiveRecord 3.1
        def exec_insert(sql, name = nil, binds = [], pk = nil, sequence_name = nil, returning: nil)
          sql, binds = sql_for_insert(sql, pk, binds, returning)
          type_casted_binds = type_casted_binds(binds)

          log(sql, name, binds, type_casted_binds) do
            cached = false
            cursor = nil
            returning_id_col = returning_id_index = nil
            with_retry do
              if binds.nil? || binds.empty?
                cursor = _connection.prepare(sql)
              else
                unless @statements.key?(sql)
                  @statements[sql] = _connection.prepare(sql)
                end

                cursor = @statements[sql]

                cursor.bind_params(type_casted_binds)

                if /:returning_id/.match?(sql)
                  # it currently expects that returning_id comes last part of binds
                  returning_id_index = binds.size
                  cursor.bind_returning_param(returning_id_index, Integer)
                end

                cached = true
              end

              cursor.exec_update
            end

            rows = []
            if returning_id_index
              returning_id = cursor.get_returning_param(returning_id_index, Integer).to_i
              rows << [returning_id]
            end
            cursor.close unless cached
            build_result(columns: returning_id_col || [], rows: rows)
          end
        end

        # New method in ActiveRecord 3.1
        def exec_update(sql, name = nil, binds = [])
          type_casted_binds = type_casted_binds(binds)

          log(sql, name, binds, type_casted_binds) do
            with_retry do
              cached = false
              if binds.nil? || binds.empty?
                cursor = _connection.prepare(sql)
              else
                if @statements.key?(sql)
                  cursor = @statements[sql]
                else
                  cursor = @statements[sql] = _connection.prepare(sql)
                end

                cursor.bind_params(type_casted_binds)

                cached = true
              end

              res = cursor.exec_update
              cursor.close unless cached
              res
            end
          end
        end

        alias :exec_delete :exec_update

        def returning_column_values(result)
          result.rows.first
        end

        def begin_db_transaction # :nodoc:
          _connection.autocommit = false
        end

        def transaction_isolation_levels
          # Oracle database supports `READ COMMITTED` and `SERIALIZABLE`
          # No read uncommitted nor repeatable read supppoted
          # http://docs.oracle.com/cd/E11882_01/server.112/e26088/statements_10005.htm#SQLRF55422
          {
            read_committed:   "READ COMMITTED",
            serializable:     "SERIALIZABLE"
          }
        end

        def begin_isolated_db_transaction(isolation)
          begin_db_transaction
          execute "SET TRANSACTION ISOLATION LEVEL  #{transaction_isolation_levels.fetch(isolation)}"
        end

        def commit_db_transaction # :nodoc:
          _connection.commit
        ensure
          _connection.autocommit = true
        end

        def exec_rollback_db_transaction # :nodoc:
          _connection.rollback
        ensure
          _connection.autocommit = true
        end

        def create_savepoint(name = current_savepoint_name) # :nodoc:
          execute("SAVEPOINT #{name}", "TRANSACTION")
        end

        def exec_rollback_to_savepoint(name = current_savepoint_name) # :nodoc:
          execute("ROLLBACK TO #{name}", "TRANSACTION")
        end

        def release_savepoint(name = current_savepoint_name) # :nodoc:
          # there is no RELEASE SAVEPOINT statement in Oracle
        end

        # Returns default sequence name for table.
        # Will take all or first 26 characters of table name and append _seq suffix
        def default_sequence_name(table_name, primary_key = nil)
          table_name.to_s.gsub((/(^|\.)([\w$-]{1,#{sequence_name_length - 4}})([\w$-]*)$/), '\1\2_seq')
        end

        def insert_fixtures_set(fixture_set, tables_to_delete = [])
          disable_referential_integrity do
            transaction(requires_new: true) do
              tables_to_delete.each { |table| delete "DELETE FROM #{quote_table_name(table)}", "Fixture Delete" }

              fixture_set.each do |table_name, rows|
                next if rows.empty?
                insert_fixtures_using_binds(table_name, rows)
              end
            end
          end
        end

        # Inserts fixture rows using a single prepared statement and bound variables
        # It follows a similar logic to #build_fixture_sql but more efficient and supports large LOBs
        def insert_fixtures_using_binds(table_name, rows)
          columns = schema_cache.columns_hash(table_name).reject do |_, column|
            supports_virtual_columns? && column.virtual?
          end

          # Get column names from all fixtures (union of all keys)
          fixture_column_names = rows.first.stringify_keys.keys

          # Check for unknown columns (same as build_fixture_sql)
          unknown_columns = fixture_column_names - columns.keys
          if unknown_columns.any?
            raise Fixture::FixtureError, %(table "#{table_name}" has no columns named #{unknown_columns.map(&:inspect).join(', ')}.)
          end

          return if fixture_column_names.empty?

          # Build SQL with bind placeholders
          quoted_columns = fixture_column_names.map { |col| quote_column_name(col) }.join(", ")
          bind_placeholders = fixture_column_names.each_with_index.map { |_, i| ":#{i + 1}" }.join(", ")
          sql = "INSERT INTO #{quote_table_name(table_name)} (#{quoted_columns}) VALUES (#{bind_placeholders})"

          # Prepare statement once and reuse for all rows
          cursor = _connection.prepare(sql)
          begin
            rows.each do |row|
              fixture = row.stringify_keys

              # Build type-casted bind values for this row (same serialization as build_fixture_sql)
              bind_values = fixture_column_names.map do |name|
                column = columns[name]
                type = lookup_cast_type_from_column(column)
                serialized = with_yaml_fallback(type.serialize(fixture[name]))
                # Apply connection-level type casting (handles LOBs -> OCI8::CLOB/BLOB/NCLOB)
                type_cast(serialized)
              end

              cursor.bind_params(bind_values)
              cursor.exec_update
            end
          ensure
            cursor.close
          end
        end

        # Oracle Database does not support this feature
        # Refer https://community.oracle.com/ideas/13845 and consider to vote
        # if you need this feature.
        def empty_insert_statement_value
          raise NotImplementedError
        end

        private
          def with_retry
            _connection.with_retry do
              yield
            rescue
              @statements.clear
              raise
            end
          end

          def handle_warnings(sql)
            @notice_receiver_sql_warnings.each do |warning|
              next if warning_ignored?(warning)

              warning.sql = sql
              ActiveRecord.db_warnings_action.call(warning)
            end
          end
      end
    end
  end
end
