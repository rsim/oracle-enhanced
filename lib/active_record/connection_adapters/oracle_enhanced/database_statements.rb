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
          raw_sql = intent.raw_sql
          original_binds_count = intent.binds.size
          sql, binds = sql_for_insert(raw_sql, pk, intent.binds, returning)
          intent.raw_sql = sql
          intent.binds = binds

          type_casted_binds = intent.type_casted_binds
          bind_specs = returning_bind_specs(binds, original_binds_count)

          log(intent) do
            cached = false
            cursor = nil
            with_raw_connection do |raw_connection|
              with_retry do
                if binds.nil? || binds.empty?
                  cursor = raw_connection.prepare(sql)
                else
                  if prepared_statements?
                    @statements[sql] ||= raw_connection.prepare(sql)
                    cursor = @statements[sql]
                    cached = true
                  else
                    cursor = raw_connection.prepare(sql)
                  end

                  cursor.bind_params(type_casted_binds)

                  bind_specs.each do |position, klass|
                    cursor.bind_returning_param(position, klass)
                  end
                end

                cursor.exec_update
              rescue
                (cursor.close rescue nil) if cursor && !cached
                raise
              end

              rows = []
              unless bind_specs.empty?
                values = bind_specs.map do |position, klass|
                  value = cursor.get_returning_param(position, klass)
                  klass == Integer ? value.to_i : value
                end
                rows << values
              end
              cursor.close unless cached
              build_result(columns: [], rows: rows)
            end
          end
        end

        def begin_db_transaction # :nodoc:
          with_raw_connection(allow_retry: true, materialize_transactions: false) do |conn|
            conn.autocommit = false
          end
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
          with_raw_connection(allow_retry: false, materialize_transactions: true) do |conn|
            conn.commit
          ensure
            conn.autocommit = true
          end
        end

        def exec_rollback_db_transaction # :nodoc:
          with_raw_connection(allow_retry: false, materialize_transactions: true) do |conn|
            conn.rollback
          ensure
            conn.autocommit = true
          end
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
          if ActiveRecord::Base.pluralize_table_names
            klass = table_name.to_s.singularize.camelize
          else
            klass = table_name.to_s.camelize
          end

          klass = klass.constantize rescue nil
          if klass.respond_to?(:ancestors) && klass.ancestors.include?(ActiveRecord::Base) &&
              !klass.lob_columns.empty?
            # write_lobs needs a transaction; SELECT ... FOR UPDATE outside one raises ORA-01002.
            transaction do
              super
              write_lobs(table_name, klass, fixture, klass.lob_columns)
            end
          else
            super
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

        # Oracle Database does not support the standard `INSERT INTO ... DEFAULT VALUES`
        # syntax. Refer https://community.oracle.com/ideas/13845 and consider to vote
        # if you need this feature.
        # We fall back to a column-list INSERT whose value is the column's DEFAULT
        # expression, which Oracle accepts and which lets the database fill the
        # column(s) from their declared defaults — typically a
        # `GENERATED BY DEFAULT AS IDENTITY` primary key, which is the case that
        # motivated this fallback. See "DEFAULT" under `values_clause` in the Oracle
        # SQL Language Reference:
        #   https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html
        # Composite primary keys produce a multi-column `(c1, c2) VALUES (DEFAULT, DEFAULT)`
        # form. Whether the resulting statement actually succeeds depends on whether
        # those columns have usable defaults — that is the caller's concern.
        def empty_insert_statement_value(primary_key = nil)
          raise NotImplementedError if primary_key.nil?

          cols = Array(primary_key)
          quoted_cols = cols.map { |c| quote_column_name(c) }.join(", ")
          defaults = (["DEFAULT"] * cols.size).join(", ")
          "(#{quoted_cols}) VALUES (#{defaults})"
        end

        def build_insert_sql(insert) # :nodoc:
          return build_merge_sql(insert) if insert.skip_duplicates? || insert.update_duplicates?

          # INSERT ALL cannot carry RETURNING; `insert.returning` is dropped and `result.rows` is empty.
          rows_sql = compile_per_row_values(insert).map do |row_values|
            "  #{insert.into} #{row_values}"
          end.join("\n")
          "INSERT ALL\n#{rows_sql}\nSELECT 1 FROM DUAL"
        end

        # Writes LOB values from attributes for specified columns
        def write_lobs(table_name, klass, attributes, columns) # :nodoc:
          pk_predicate = Array(klass.primary_key).map { |pk|
            "#{quote_column_name(pk)} = #{quote(attributes[pk])}"
          }.join(" AND ")

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
                WHERE #{pk_predicate} FOR UPDATE
              SQL
                raise ActiveRecord::RecordNotFound, "statement #{sql} returned no rows"
              end
              lob = lob_record[col.name]
              with_raw_connection do |conn|
                conn.write_lob(lob, value.to_s, col.type == :binary)
              end
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

          def sql_for_insert(sql, pk, binds, returning) # :nodoc:
            table_ref = extract_table_ref_from_insert_sql(sql)
            # Mirror AbstractAdapter#sql_for_insert: when caller passes pk: nil,
            # infer the primary key from the SQL via the schema cache so that
            # generic `connection.exec_insert(sql, name, binds)` callers also
            # benefit from RETURNING auto-fetch.
            pk = schema_cache.primary_keys(table_ref) if pk.nil? && table_ref
            cols = columns_for_returning_clause(sql, pk, binds, returning)
            unless cols.empty?
              quoted_cols = cols.map { |c| quote_column_name(c) }.join(", ")
              placeholders = cols.map { |c| ":returning_#{c}" }.join(", ")
              sql = "#{sql} RETURNING #{quoted_cols} INTO #{placeholders}"
              binds = binds.dup
              cols.each do |col|
                column = table_ref ? columns(table_ref).find { |c| c.name == col } : nil
                type = column&.cast_type || Type::OracleEnhanced::Integer.new
                binds << ActiveRecord::Relation::QueryAttribute.new("returning_#{col}", nil, type)
              end
            end
            # Skip super: AR's abstract appends PG-style `RETURNING col1, col2` which conflicts with Oracle's `RETURNING ... INTO :bind` form (ORA-00925).
            [sql, binds]
          end

          def columns_for_returning_clause(sql, pk, binds, returning)
            cols = if returning.is_a?(Array) && !returning.empty?
              returning.map(&:to_s)
            elsif pk.is_a?(Array)
              pk.map(&:to_s)
            elsif pk.is_a?(Symbol) || pk.is_a?(String)
              [pk.to_s]
            else
              []
            end
            cols.reject do |col|
              next true if binds.any? { |bind| bind.name == col }
              # The all-defaults form (`VALUES (DEFAULT)` for single PK,
              # `VALUES (DEFAULT, DEFAULT, ...)` for composite PK) needs RETURNING
              # to read back the database-generated values, so do not let the
              # column-list rejection below drop these columns from RETURNING.
              next false if sql.match?(/VALUES\s*\(\s*DEFAULT(?:\s*,\s*DEFAULT)*\s*\)/i)
              sql.include?(quote_column_name(col))
            end
          end

          # Identify the trailing binds appended by `sql_for_insert` by position, not by name,
          # so a user column happening to share the placeholder name cannot collide.
          def returning_bind_specs(binds, original_binds_count)
            return [] if binds.size <= original_binds_count
            (original_binds_count...binds.size).map do |i|
              klass = binds[i].type.is_a?(ActiveModel::Type::String) ? String : Integer
              [i + 1, klass]
            end
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
                if prepared_statements?
                  @statements[sql] ||= raw_connection.prepare(sql)
                  cursor = @statements[sql]
                  cached = true
                else
                  cursor = raw_connection.prepare(sql)
                end

                cursor.bind_params(type_casted_binds)
              end
              cursor.exec
            rescue
              (cursor.close rescue nil) if cursor && !cached
              raise
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
              @statements.clear if prepared_statements?
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

          # Compile each insert row to `VALUES (...)` individually via Arel, so
          # we can interleave each row between `INTO ... VALUES` for Oracle's
          # multi-table INSERT ALL form. Mirrors the per-row coercion that
          # ActiveRecord::InsertAll::Builder#values_list applies before bundling
          # rows into a single `VALUES (...), (...)` fragment.
          def compile_per_row_values(insert)
            rows = compile_per_row_coerced_values(insert)
            rows.map { |row| visitor.compile(Arel::Nodes::ValuesList.new([row])) }
          end

          # Shared coercion used by both INSERT ALL (compile_per_row_values) and
          # MERGE (compile_per_row_select_aliases). Returns Array<Array> where each
          # inner array is a row of pre-quoting coerced values aligned with
          # `keys_including_timestamps`.
          def compile_per_row_coerced_values(insert)
            insert_all = insert.send(:insert_all)
            keys = insert.keys_including_timestamps
            # Raise early on unknown columns so callers get
            # ActiveModel::UnknownAttributeError instead of ORA-00904. Mirrors
            # the guard inside AR core's private Builder#extract_types_for.
            unknown_column = (keys - insert.model.columns_hash.keys).first
            raise ActiveModel::UnknownAttributeError.new(insert.model.new, unknown_column) if unknown_column

            types = keys.index_with { |key| insert.model.type_for_attribute(key) }
            primary_keys = insert_all.primary_keys.to_set

            insert_all.map_key_with_value do |key, value|
              if Arel::Nodes::SqlLiteral === value
                value
              elsif primary_keys.include?(key) && value.nil?
                default_insert_value(insert_all.model.columns_hash[key])
              else
                type = types[key]
                ActiveModel::Type::SerializeCastValue.serialize(type, type.cast(value))
              end
            end
          end

          # Compile each insert row to `SELECT v1 AS col1, v2 AS col2 FROM DUAL`,
          # the per-row shape Oracle MERGE's `USING (...) s` source needs. Combined
          # with `UNION ALL` between rows in build_merge_sql.
          def compile_per_row_select_aliases(insert)
            aliases = insert.keys_including_timestamps.map { |k| quote_column_name(k) }
            compile_per_row_coerced_values(insert).map do |row|
              pairs = row.zip(aliases).map do |value, col_alias|
                sql_value = Arel::Nodes::SqlLiteral === value ? visitor.compile(value) : quote(value)
                "#{sql_value} AS #{col_alias}"
              end
              "SELECT #{pairs.join(", ")} FROM DUAL"
            end
          end

          # Bridge AR's :skip / :update on_duplicate semantics to Oracle MERGE.
          # `unique_by:` drives the ON clause; if omitted, falls back to the
          # table's primary key (matches AR core's Builder#conflict_target for
          # :update, and extends the same fallback to :skip — Oracle has no
          # equivalent to PG's bare `ON CONFLICT DO NOTHING`). ON-clause columns
          # are excluded from `WHEN MATCHED THEN UPDATE SET` (ORA-38104).
          # RETURNING is not emitted (Oracle MERGE does not carry it in standard
          # SQL); `result.rows` is empty, mirroring the existing INSERT ALL path.
          def build_merge_sql(insert)
            insert_all = insert.send(:insert_all)
            on_columns = merge_on_columns(insert_all)

            if on_columns.empty?
              raise ArgumentError,
                    "Oracle MERGE-based insert_all/upsert_all requires :unique_by or " \
                    "a primary key to drive the ON clause; neither is available on " \
                    "#{insert_all.model.name}."
            end

            target = insert_all.model.quoted_table_name
            keys = insert.keys_including_timestamps
            quoted_cols = keys.map { |k| quote_column_name(k) }
            using_select = compile_per_row_select_aliases(insert).join(" UNION ALL ")
            on_clause = on_columns.map { |c|
              q = quote_column_name(c)
              "t.#{q} = s.#{q}"
            }.join(" AND ")

            sql = +"MERGE INTO #{target} t\nUSING (#{using_select}) s\nON (#{on_clause})\n"

            if insert.update_duplicates?
              update_pairs = merge_update_pairs(insert, on_columns)
              sql << "WHEN MATCHED THEN UPDATE SET #{update_pairs}\n" unless update_pairs.empty?
            end

            insert_cols_csv = quoted_cols.join(", ")
            insert_vals_csv = quoted_cols.map { |c| "s.#{c}" }.join(", ")
            sql << "WHEN NOT MATCHED THEN INSERT (#{insert_cols_csv}) VALUES (#{insert_vals_csv})"
            sql
          end

          def merge_on_columns(insert_all)
            cols = insert_all.unique_by ? Array(insert_all.unique_by.columns) : Array(insert_all.primary_keys)
            cols.map(&:to_s)
          end

          # Build the `WHEN MATCHED THEN UPDATE SET` clause. Auto-filled
          # `updated_at`-style columns get a no-change CASE guard so idempotent
          # upserts don't bump them — mirrors AR core's
          # Builder#touch_model_timestamps_unless.
          def merge_update_pairs(insert, on_columns)
            on_set = on_columns.map { |c| c.to_s.downcase }.to_set
            updatable = insert.keys_including_timestamps.reject { |k| on_set.include?(k.to_s.downcase) }
            return "" if updatable.empty?

            # `insert_all.updatable_columns` is `keys - readonly - unique_by` —
            # user-supplied columns only, so auto-filled timestamps don't poison
            # the no-change comparison.
            user_updatable = insert.send(:insert_all).updatable_columns.map(&:to_s).reject { |k| on_set.include?(k.downcase) }
            auto_filled_ts = auto_filled_update_timestamps(insert, updatable)
            guard = no_change_predicate(user_updatable) unless user_updatable.empty?

            updatable.map { |column|
              q = quote_column_name(column)
              if guard && auto_filled_ts.include?(column.to_s)
                "t.#{q} = CASE WHEN #{guard} THEN t.#{q} ELSE s.#{q} END"
              else
                "t.#{q} = s.#{q}"
              end
            }.join(", ")
          end

          # AND-joined per-column NULL-safe equality between target (`t`) and
          # source (`s`); drives the no-change CASE guard in merge_update_pairs.
          def no_change_predicate(columns)
            columns.map { |column|
              q = quote_column_name(column)
              "(t.#{q} = s.#{q} OR (t.#{q} IS NULL AND s.#{q} IS NULL))"
            }.join(" AND ")
          end

          def auto_filled_update_timestamps(insert, updatable)
            return [] unless insert.record_timestamps?

            user_supplied = insert.keys.map(&:to_s).to_set
            ts_cols = insert.model.timestamp_attributes_for_update_in_model.map(&:to_s).to_set
            updatable.map(&:to_s).select { |k| ts_cols.include?(k) && !user_supplied.include?(k) }
          end
      end
    end
  end
end
