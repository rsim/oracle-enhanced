# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DbmsOutput
        # DBMS_OUTPUT =============================================
        #
        # PL/SQL in Oracle uses dbms_output for logging print statements
        # These methods stick that output into the Rails log so Ruby and PL/SQL
        # code can can be debugged together in a single application

        # Maximum DBMS_OUTPUT buffer size
        DBMS_OUTPUT_BUFFER_SIZE = 10000  # can be 1-1000000

        # Turn DBMS_Output logging on
        def enable_dbms_output
          set_dbms_output_plsql_connection
          @enable_dbms_output = true
          plsql(:dbms_output).sys.dbms_output.enable(DBMS_OUTPUT_BUFFER_SIZE)
        end
        # Turn DBMS_Output logging off
        def disable_dbms_output
          set_dbms_output_plsql_connection
          @enable_dbms_output = false
          plsql(:dbms_output).sys.dbms_output.disable
        end
        # Is DBMS_Output logging enabled?
        def dbms_output_enabled?
          @enable_dbms_output
        end

      private
        def log(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = nil, async: false, &block)
          @instrumenter.instrument(
            "sql.active_record",
            sql:               sql,
            name:              name,
            binds:             binds,
            type_casted_binds: type_casted_binds,
            statement_name:    statement_name,
            async:             async,
            connection:        self,
            &block
          )
        rescue => e
          # FIXME: raise ex.set_query(sql, binds)
          raise translate_exception_class(e, sql, binds)
        ensure
          log_dbms_output if dbms_output_enabled?
        end

        def set_dbms_output_plsql_connection
          raise OracleEnhanced::ConnectionException, "ruby-plsql gem is required for logging DBMS output" unless self.respond_to?(:plsql)
          # do not reset plsql connection if it is the same (as resetting will clear PL/SQL metadata cache)
          unless plsql(:dbms_output).connection && plsql(:dbms_output).connection.raw_connection == raw_connection
            plsql(:dbms_output).connection = raw_connection
          end
        end

        def log_dbms_output
          while true do
            result = plsql(:dbms_output).sys.dbms_output.get_line(line: "", status: 0)
            break unless result[:status] == 0
            @logger.debug "DBMS_OUTPUT: #{result[:line]}" if @logger
          end
        end
      end
    end
  end
end
