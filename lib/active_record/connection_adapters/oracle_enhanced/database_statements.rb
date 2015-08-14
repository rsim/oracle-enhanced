module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseStatements
        # DATABASE STATEMENTS ======================================
        #
        # see: abstract/database_statements.rb

        # Executes a SQL statement
        def execute(sql, name = nil)
          log(sql, name) { @connection.exec(sql) }
        end

        def clear_cache!
          @statements.clear
          reload_type_map
        end

        def exec_query(sql, name = 'SQL', binds = [])
          type_casted_binds = binds.map { |col, val|
            [col, type_cast(val, col)]
          }
          log(sql, name, type_casted_binds) do
            cursor = nil
            cached = false
            if without_prepared_statement?(binds)
              cursor = @connection.prepare(sql)
            else
              unless @statements.key? sql
                @statements[sql] = @connection.prepare(sql)
              end

              cursor = @statements[sql]

              type_casted_binds.each_with_index do |bind, i|
                col, val = bind
                cursor.bind_param(i + 1, val, col)
              end

              cached = true
            end

            cursor.exec

            if name == 'EXPLAIN' and sql =~ /^EXPLAIN/
              res = true
            else
              columns = cursor.get_col_names.map do |col_name|
                @connection.oracle_downcase(col_name)
              end
              rows = []
              fetch_options = {:get_lob_value => (name != 'Writable Large Object')}
              while row = cursor.fetch(fetch_options)
                rows << row
              end
              res = ActiveRecord::Result.new(columns, rows)
            end

            cursor.close unless cached
            res
          end
        end

        def supports_statement_cache?
          true
        end

        def supports_explain?
          true
        end

        def explain(arel, binds = [])
          sql = "EXPLAIN PLAN FOR #{to_sql(arel, binds)}"
          return if sql =~ /FROM all_/
          if ORACLE_ENHANCED_CONNECTION == :jdbc
            exec_query(sql, 'EXPLAIN', binds)
          else
            exec_query(sql, 'EXPLAIN')
          end
          select_values("SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)", 'EXPLAIN').join("\n")
        end

        # Returns an array of arrays containing the field values.
        # Order is the same as that returned by #columns.
        def select_rows(sql, name = nil, binds = [])
          exec_query(sql, name, binds).rows
        end

        # Executes an INSERT statement and returns the new record's ID
        def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) #:nodoc:
          # if primary key value is already prefetched from sequence
          # or if there is no primary key
          if id_value || pk.nil?
            execute(sql, name)
            return id_value
          end

          sql_with_returning = sql + @connection.returning_clause(quote_column_name(pk))
          log(sql, name) do
            @connection.exec_with_returning(sql_with_returning)
          end
        end
        protected :insert_sql

        # New method in ActiveRecord 3.1
        # Will add RETURNING clause in case of trigger generated primary keys
        def sql_for_insert(sql, pk, id_value, sequence_name, binds)
          unless id_value || pk.nil? || (defined?(CompositePrimaryKeys) && pk.kind_of?(CompositePrimaryKeys::CompositeKeys))
            sql = "#{sql} RETURNING #{quote_column_name(pk)} INTO :returning_id"
            returning_id_col = new_column("returning_id", nil, Type::Value.new, "number", true, "dual", true, true)
            (binds = binds.dup) << [returning_id_col, nil]
          end
          [sql, binds]
        end

        # New method in ActiveRecord 3.1
        def exec_insert(sql, name, binds, pk = nil, sequence_name = nil)
          type_casted_binds = binds.map { |col, val|
            [col, type_cast(val, col)]
          }
          log(sql, name, type_casted_binds) do
            returning_id_col = returning_id_index = nil
            if without_prepared_statement?(binds)
              cursor = @connection.prepare(sql)
            else
              unless @statements.key? (sql)
                @statements[sql] = @connection.prepare(sql)
              end

              cursor = @statements[sql]

              type_casted_binds.each_with_index do |bind, i|
                col, val = bind
                if col.returning_id?
                  returning_id_col = [col]
                  returning_id_index = i + 1
                  cursor.bind_returning_param(returning_id_index, Integer)
                else
                  cursor.bind_param(i + 1, val, col)
                end
              end
            end

            cursor.exec_update

            rows = []
            if returning_id_index
              returning_id = cursor.get_returning_param(returning_id_index, Integer)
              rows << [returning_id]
            end
            ActiveRecord::Result.new(returning_id_col || [], rows)
          end
        end

        # New method in ActiveRecord 3.1
        def exec_update(sql, name, binds)
          type_casted_binds = binds.map { |col, val|
            [col, type_cast(val, col)]
          }
          log(sql, name, type_casted_binds) do
            cached = false
            if without_prepared_statement?(binds)
              cursor = @connection.prepare(sql)
            else
              cursor = if @statements.key?(sql)
                @statements[sql]
              else
                @statements[sql] = @connection.prepare(sql)
              end

              type_casted_binds.each_with_index do |bind, i|
                col, val = bind
                cursor.bind_param(i + 1, val, col)
              end
              cached = true
            end

            res = cursor.exec_update
            cursor.close unless cached
            res
          end
        end

        alias :exec_delete :exec_update

        def begin_db_transaction #:nodoc:
          @connection.autocommit = false
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

        def commit_db_transaction #:nodoc:
          @connection.commit
        ensure
          @connection.autocommit = true
        end

        def exec_rollback_db_transaction #:nodoc:
          @connection.rollback
        ensure
          @connection.autocommit = true
        end

        def create_savepoint(name = current_savepoint_name) #:nodoc:
          execute("SAVEPOINT #{name}")
        end

        def exec_rollback_to_savepoint(name = current_savepoint_name) #:nodoc:
          execute("ROLLBACK TO #{name}")
        end

        def release_savepoint(name = current_savepoint_name) #:nodoc:
          # there is no RELEASE SAVEPOINT statement in Oracle
        end

        # Returns default sequence name for table.
        # Will take all or first 26 characters of table name and append _seq suffix
        def default_sequence_name(table_name, primary_key = nil)
          table_name.to_s.gsub (/(^|\.)([\w$-]{1,#{sequence_name_length-4}})([\w$-]*)$/), '\1\2_seq'
        end

        # Inserts the given fixture into the table. Overridden to properly handle lobs.
        def insert_fixture(fixture, table_name) #:nodoc:
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

        private

        def select(sql, name = nil, binds = [])
          exec_query(sql, name, binds)
        end

      end
    end
  end
end
