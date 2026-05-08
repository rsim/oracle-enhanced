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
            with_retry do
              if binds.nil? || binds.empty?
                cursor = _connection.prepare(sql)
              else
                if prepared_statements?
                  @statements[sql] ||= _connection.prepare(sql)
                  cursor = @statements[sql]
                  cached = true
                else
                  cursor = _connection.prepare(sql)
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
          if insert.update_duplicates?
            return build_merge_sql(insert, on_duplicate: :update)
          elsif insert.skip_duplicates?
            return build_merge_sql(insert, on_duplicate: :skip)
          end

          rows = split_values_list(insert.values_list)
          model = insert.send(:model)
          pk = model.primary_key
          pk_in_keys = pk.is_a?(String) || pk.is_a?(Symbol) ?
            insert.send(:keys_including_timestamps).include?(pk.to_s) : true

          if pk_in_keys
            # Standard INSERT ALL path. AR's `returning:` does NOT round-trip --
            # INSERT ALL cannot carry a RETURNING clause per Oracle SQL Reference.
            rows_sql = rows.map { |row| "  #{insert.into} VALUES #{row}" }.join("\n")
            "INSERT ALL\n#{rows_sql}\nSELECT 1 FROM DUAL"
          else
            # Auto-PK injection path. INSERT ALL evaluates `seq.NEXTVAL` only
            # once per statement (causing ORA-00001), so we route through
            # `INSERT INTO t (...) SELECT seq.NEXTVAL, ... FROM dual UNION ALL ...`
            # where NEXTVAL is evaluated per row of the SELECT.
            build_insert_select_with_nextval(insert, rows)
          end
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

          def sql_for_insert(sql, pk, binds, returning) # :nodoc:
            cols = columns_for_returning_clause(sql, pk, binds, returning)
            unless cols.empty?
              table_name = extract_table_ref_from_insert_sql(sql)
              quoted_cols = cols.map { |c| quote_column_name(c) }.join(", ")
              placeholders = cols.map { |c| ":returning_#{c}" }.join(", ")
              sql = "#{sql} RETURNING #{quoted_cols} INTO #{placeholders}"
              binds = binds.dup
              cols.each do |col|
                column = table_name ? columns(table_name).find { |c| c.name == col } : nil
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

          # PoC: when the PK isn't supplied, wrap the values in a subquery and
          # SELECT seq.NEXTVAL from the outer query. Oracle disallows NEXTVAL
          # directly inside `UNION ALL` branches (ORA-02287), so we layer it as:
          #
          #   INSERT INTO t (pk, col1, col2)
          #   SELECT seq.NEXTVAL, col1, col2 FROM (
          #     SELECT 'a' AS col1, 1 AS col2 FROM dual UNION ALL
          #     SELECT 'b' AS col1, 2 AS col2 FROM dual
          #   )
          def build_insert_select_with_nextval(insert, rows)
            model = insert.send(:model)
            pk = model.primary_key
            seq_name = default_sequence_name(model.table_name, nil)
            unless seq_name && oracle_sequence_exists?(seq_name)
              raise NotImplementedError,
                    "Oracle insert_all without explicit primary key requires a sequence " \
                    "named #{seq_name.inspect} for the table; none found."
            end

            quoted_seq = "#{quote_table_name(seq_name)}.NEXTVAL"
            keys = insert.send(:keys_including_timestamps)
            new_into = insert.into.sub(/\(([^)]*)\)\z/) { "(#{quote_column_name(pk)}, #{$1})" }

            inner_select = rows.map do |row|
              tuple = split_tuple(row)
              aliases = keys.zip(tuple).map { |k, v| "#{v} AS #{quote_column_name(k)}" }
              "SELECT #{aliases.join(", ")} FROM dual"
            end.join(" UNION ALL ")

            outer_cols = keys.map { |k| quote_column_name(k) }.join(", ")
            "INSERT #{new_into} SELECT #{quoted_seq}, #{outer_cols} FROM (#{inner_select})"
          end

          def oracle_sequence_exists?(seq_name)
            select_value(<<~SQL.squish, "SCHEMA", [bind_string("seq_name", seq_name.upcase)]).to_i.positive?
              SELECT COUNT(*) FROM all_sequences
               WHERE sequence_owner = SYS_CONTEXT('userenv', 'current_schema')
                 AND sequence_name = :seq_name
            SQL
          end

          # PoC: emit a MERGE statement to bridge AR's `:skip` / `:update` semantics.
          # Requires `unique_by:` to be supplied so we can build the ON clause.
          # Limitations: no `returning:` (Oracle MERGE does not carry RETURNING in
          # standard versions); composite/expression unique_by not exercised.
          def build_merge_sql(insert, on_duplicate:)
            insert_all = insert.send(:insert_all)
            unique_by = insert_all.unique_by or
              raise NotImplementedError, "Oracle MERGE-based insert_all requires :unique_by to identify the conflict target"

            model = insert.send(:model)
            target = quote_table_name(model.table_name)

            # PoC: MERGE path expects explicit values (including PK) -- auto-PK
            # injection isn't applied here because the conflict target normally
            # IS the primary key, so a fresh seq.NEXTVAL would never match.
            into = insert.into
            rows = split_values_list(insert.values_list)
            keys_match = into.match(/\(([^)]*)\)\z/)
            quoted_keys_csv = keys_match ? keys_match[1] : ""
            keys = quoted_keys_csv.scan(/"([^"]+)"/).flatten

            using_select = rows.map do |row|
              tuple = split_tuple(row)
              pairs = keys.zip(tuple).map { |k, v| "#{v} AS #{quote_column_name(k)}" }
              "SELECT #{pairs.join(", ")} FROM dual"
            end.join(" UNION ALL ")

            on_columns = Array(unique_by.columns).map(&:to_s)
            on_clause = on_columns.map { |c| "t.#{quote_column_name(c)} = s.#{quote_column_name(c)}" }.join(" AND ")

            insert_vals = keys.map { |k| "s.#{quote_column_name(k)}" }.join(", ")

            sql = +"MERGE INTO #{target} t\n"
            sql << "USING (#{using_select}) s\n"
            sql << "ON (#{on_clause})\n"

            if on_duplicate == :update
              on_set = on_columns.map(&:downcase).to_set
              updatable = keys.reject { |k| on_set.include?(k.downcase) }
              update_cols = updatable.map { |k| "t.#{quote_column_name(k)} = s.#{quote_column_name(k)}" }.join(", ")
              sql << "WHEN MATCHED THEN UPDATE SET #{update_cols}\n" unless update_cols.empty?
            end

            sql << "WHEN NOT MATCHED THEN INSERT (#{quoted_keys_csv}) VALUES (#{insert_vals})"
            sql
          end

          # Split a `(...)` row tuple into individual value strings while tracking
          # nested parens and single-quoted string literals (with `''` escapes).
          def split_tuple(row)
            inside = row[1..-2]
            values = []
            current = +""
            depth = 0
            in_string = false
            i = 0
            while i < inside.length
              c = inside[i]
              if in_string
                if c == "'" && inside[i + 1] == "'"
                  current << "''"
                  i += 2
                  next
                elsif c == "'"
                  in_string = false
                end
                current << c
              else
                case c
                when "'"
                  in_string = true
                  current << c
                when "("
                  depth += 1
                  current << c
                when ")"
                  depth -= 1
                  current << c
                when ","
                  if depth.zero?
                    values << current
                    current = +""
                  else
                    current << c
                  end
                else
                  current << c
                end
              end
              i += 1
            end
            values << current unless current.empty?
            values
          end

          # Split a `VALUES (...), (...)` SQL fragment into individual `(...)` row
          # tuples, tracking nested parens and single-quoted string literals (with
          # `''` escapes) so values containing those characters parse correctly.
          def split_values_list(values_list)
            body = values_list.sub(/\AVALUES\s*/, "")
            rows = []
            depth = 0
            in_string = false
            start_idx = nil
            i = 0
            while i < body.length
              c = body[i]
              if in_string
                if c == "'" && body[i + 1] == "'"
                  i += 2
                  next
                elsif c == "'"
                  in_string = false
                end
              else
                case c
                when "'"
                  in_string = true
                when "("
                  start_idx = i if depth.zero?
                  depth += 1
                when ")"
                  depth -= 1
                  if depth.zero?
                    rows << body[start_idx..i]
                    start_idx = nil
                  end
                end
              end
              i += 1
            end
            rows
          end
      end
    end
  end
end
