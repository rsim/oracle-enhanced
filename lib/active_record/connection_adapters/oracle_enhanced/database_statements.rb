# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseStatements
        # DATABASE STATEMENTS ======================================
        #
        # see: abstract/database_statements.rb

        # Executes a SQL statement
        def execute(sql, name = nil, async: false, allow_retry: false)
          sql = transform_query(sql)

          log(sql, name, async: async) { _connection.exec(sql, allow_retry: allow_retry) }
        end

        def exec_query(sql, name = "SQL", binds = [], prepare: false, async: false)
          sql = transform_query(sql)

          type_casted_binds = type_casted_binds(binds)

          log(sql, name, binds, type_casted_binds, async: async) do
            cursor = nil
            cached = false
            with_retry do
              if without_prepared_statement?(binds)
                cursor = _connection.prepare(sql)
              else
                unless @statements.key? sql
                  @statements[sql] = _connection.prepare(sql)
                end

                cursor = @statements[sql]

                cursor.bind_params(type_casted_binds)

                cached = true
              end

              cursor.exec
            end

            if (name == "EXPLAIN") && sql.start_with?("EXPLAIN")
              res = true
            else
              columns = cursor.get_col_names.map do |col_name|
                oracle_downcase(col_name)
              end
              rows = []
              fetch_options = { get_lob_value: (name != "Writable Large Object") }
              while row = cursor.fetch(fetch_options)
                rows << row
              end
              res = build_result(columns: columns, rows: rows)
            end

            cursor.close unless cached
            res
          end
        end
        alias_method :internal_exec_query, :exec_query

        def supports_explain?
          true
        end

        def explain(arel, binds = [])
          sql = "EXPLAIN PLAN FOR #{to_sql(arel, binds)}"
          return if /FROM all_/.match?(sql)
          if ORACLE_ENHANCED_CONNECTION == :jdbc
            exec_query(sql, "EXPLAIN", binds)
          else
            exec_query(sql, "EXPLAIN")
          end
          select_values("SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)", "EXPLAIN").join("\n")
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
          super
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
              if without_prepared_statement?(binds)
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
              if without_prepared_statement?(binds)
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
          def with_retry
            _connection.with_retry do
              yield
            rescue
              @statements.clear
              raise
            end
          end
      end
    end
  end
end
