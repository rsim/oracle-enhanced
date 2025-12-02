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

        # Executes a SQL statement
        def execute(...)
          super
        end

        # Low level execution of a SQL statement on the connection returning adapter specific result object.
        def raw_execute(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false, materialize_transactions: false)
          sql = preprocess_query(sql)

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

            # Capture ROWID for LOB writes on tables without primary keys
            # This must happen right after exec_update while the cursor still has the rowid
            if cursor.respond_to?(:rowid)
              @last_insert_rowid = cursor.rowid
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

        # Inserts the given fixture into the table. Overridden to properly handle lobs.
        def insert_fixture(fixture, table_name) # :nodoc:
          super

          if ActiveRecord::Base.pluralize_table_names
            klass = table_name.to_s.singularize.camelize
          else
            klass = table_name.to_s.camelize
          end

          klass = klass.constantize rescue nil
          if klass.respond_to?(:ancestors) && klass.ancestors.include?(ActiveRecord::Base)
            write_lobs(table_name, klass, fixture, klass.lob_columns)
          end
        end

        def insert_fixtures_set(fixture_set, tables_to_delete = [])
          disable_referential_integrity do
            transaction(requires_new: true) do
              tables_to_delete.each { |table| delete "DELETE FROM #{quote_table_name(table)}", "Fixture Delete" }

              fixture_set.each do |table_name, rows|
                rows.each { |row| insert_fixture(row, table_name) }
              end
            end
          end
        end

        # Oracle Database does not support this feature
        # Refer https://community.oracle.com/ideas/13845 and consider to vote
        # if you need this feature.
        def empty_insert_statement_value
          raise NotImplementedError
        end

        # Writes LOB values from attributes for specified columns
        def write_lobs(table_name, klass, attributes, columns) # :nodoc:
          pk = klass.primary_key

          where_clause = if pk.nil? && @last_insert_rowid
            "ROWID = #{quote(@last_insert_rowid)}"
          elsif pk.nil?
            if columns.any? { |col| attributes[col.name].present? }
              @logger&.warn "Cannot write LOB columns for #{table_name} - table has no primary key " \
                            "and ROWID is not available. LOB data may be truncated."
            end
            return
          elsif pk.is_a?(Array)
            pk.map { |col| "#{quote_column_name(col)} = #{quote(attributes[col])}" }.join(" AND ")
          else
            "#{quote_column_name(pk)} = #{quote(attributes[pk])}"
          end

          columns.each do |col|
            value = attributes[col.name]
            # changed sequence of next two lines - should check if value is nil before converting to yaml
            next unless value
            value = klass.attribute_types[col.name].serialize(value)
            # value can be nil after serialization because ActiveRecord serializes [] and {} as nil
            next unless value
            uncached do
              sql = "SELECT #{quote_column_name(col.name)} FROM #{quote_table_name(table_name)} " \
                    "WHERE #{where_clause} FOR UPDATE"
              unless lob_record = select_one(sql, "Writable Large Object")
                raise ActiveRecord::RecordNotFound, "statement #{sql} returned no rows"
              end
              lob = lob_record[col.name]
              _connection.write_lob(lob, value.to_s, col.type == :binary)
            end
          end

          # Clear the stored ROWID after use to prevent it being used for wrong row
          @last_insert_rowid = nil
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
