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

        def supports_explain?
          true
        end

        def explain(arel, binds = [], options = []) # :nodoc:
          sql = "EXPLAIN PLAN FOR #{to_sql(arel, binds)}"
          return if sql.include?("FROM all_")
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

        def insert(arel, name = nil, pk = nil, id_value = nil, sequence_name = nil, binds = [], returning: nil)
          pk = nil if id_value
          Array(super || id_value)
        end

        def _exec_insert(intent, pk = nil, sequence_name = nil, returning: nil) # :nodoc:
          sql, binds = sql_for_insert(intent.raw_sql, pk, intent.binds, returning)
          intent.raw_sql = sql
          intent.binds = binds

          type_casted_binds = intent.type_casted_binds

          log(intent) do
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

                if sql.include?(":returning_id")
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
        # Truncates the trailing identifier component (after the last +.+) by
        # bytes so the result fits within +sequence_name_length+, leaving room
        # for the +_seq+ suffix. Byte-based to match Oracle's enforcement.
        # Character class is +[[:word:]$#-]+: +[[:word:]]+ (Unicode-aware,
        # vs ASCII-only +\w+) plus +$+ and +#+ to match Oracle's unquoted
        # identifier rules (see +Quoting::NONQUOTED_OBJECT_NAME+), with +-+
        # kept for backward compatibility with quoted-identifier callers.
        def default_sequence_name(table_name, _column)
          table_name.to_s.gsub(/(\A|\.)([[:word:]$#-]+)\z/) do
            prefix = Regexp.last_match(1)
            name = Regexp.last_match(2)
            max_bytes = sequence_name_length - 4
            if name.bytesize > max_bytes
              name = name.byteslice(0, max_bytes)
              # Back off a byte at a time if the slice fell in the middle of a
              # multibyte character.
              name = name.byteslice(0, name.bytesize - 1) until name.bytesize.zero? || name.valid_encoding?
            end
            "#{prefix}#{name}_seq"
          end
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
        def empty_insert_statement_value(primary_key = nil)
          raise NotImplementedError
        end

        # Writes LOB values from attributes for specified columns
        def write_lobs(table_name, klass, attributes, columns) # :nodoc:
          id = quote(attributes[klass.primary_key])
          columns.each do |col|
            value = attributes[col.name]
            # changed sequence of next two lines - should check if value is nil before converting to yaml
            next unless value
            value = klass.attribute_types[col.name].serialize(value)
            # value can be nil after serialization because ActiveRecord serializes [] and {} as nil
            next unless value
            uncached do
              unless lob_record = select_one(sql = <<~SQL.squish, "Writable Large Object")
                SELECT #{quote_column_name(col.name)} FROM #{quote_table_name(table_name)}
                WHERE #{quote_column_name(klass.primary_key)} = #{id} FOR UPDATE
              SQL
                raise ActiveRecord::RecordNotFound, "statement #{sql} returned no rows"
              end
              lob = lob_record[col.name]
              _connection.write_lob(lob, value.to_s, col.type == :binary)
            end
          end
        end

        private
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

          # Adds RETURNING clause when the primary key is generated by the database
          # (trigger-based legacy tables or `GENERATED BY DEFAULT AS IDENTITY` columns)
          # so that Rails can read the generated value back. When the user already
          # supplied a value for the primary key column (e.g. a String VARCHAR2 PK
          # like +code: "ABC"+), the bind is present and there is nothing to read
          # back; appending RETURNING with an Integer-typed out-bind would raise
          # ORA-01722 against a non-numeric column.
          def sql_for_insert(sql, pk, binds, _returning) # :nodoc:
            if (pk.is_a?(Symbol) || pk.is_a?(String)) &&
                binds.none? { |bind| bind.name == pk.to_s }
              sql = "#{sql} RETURNING #{quote_column_name(pk)} INTO :returning_id"
              (binds = binds.dup) << ActiveRecord::Relation::QueryAttribute.new("returning_id", nil, Type::OracleEnhanced::Integer.new)
            end
            super
          end

          def returning_column_values(result)
            result.rows.first
          end

          def perform_query(raw_connection, intent)
            sql = intent.processed_sql
            binds = intent.binds
            type_casted_binds = intent.type_casted_binds

            cursor = nil
            cached = false
            with_retry do
              if binds.nil? || binds.empty?
                cursor = raw_connection.prepare(sql)
              else
                unless @statements.key? sql
                  @statements[sql] = raw_connection.prepare(sql)
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
              fetch_options = { get_lob_value: (intent.name != "Writable Large Object") }
              while row = cursor.fetch(fetch_options)
                rows << row
              end
            end

            affected_rows_count = cursor.row_count
            cursor.close unless cached

            intent.notification_payload[:affected_rows] = affected_rows_count
            intent.notification_payload[:row_count] = rows.length

            { columns: columns, rows: rows, affected_rows_count: affected_rows_count }
          end

          def with_retry
            _connection.with_retry do
              yield
            rescue
              @statements.clear
              raise
            end
          end

          def handle_warnings(raw_result, sql)
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
