begin
  require "java"
  require "jruby"

  # ojdbc14.jar file should be in JRUBY_HOME/lib or should be in ENV['PATH'] or load path

  ojdbc_jar = "ojdbc14.jar"

  unless ENV_JAVA['java.class.path'] =~ Regexp.new(ojdbc_jar)
    # On Unix environment variable should be PATH, on Windows it is sometimes Path
    env_path = ENV["PATH"] || ENV["Path"] || ''
    if ojdbc_jar_path = env_path.split(/[:;]/).concat($LOAD_PATH).find{|d| File.exists?(File.join(d,ojdbc_jar))}
      require File.join(ojdbc_jar_path,ojdbc_jar)
    end
  end

  java.sql.DriverManager.registerDriver Java::oracle.jdbc.driver.OracleDriver.new

  # set tns_admin property from TNS_ADMIN environment variable
  if !java.lang.System.get_property("oracle.net.tns_admin") && ENV["TNS_ADMIN"]
    java.lang.System.set_property("oracle.net.tns_admin", ENV["TNS_ADMIN"])
  end

rescue LoadError, NameError
  # JDBC driver is unavailable.
  raise LoadError, "ERROR: ActiveRecord oracle_enhanced adapter could not load Oracle JDBC driver. Please install ojdbc14.jar library."
end


module ActiveRecord
  module ConnectionAdapters

    # JDBC database interface for JRuby
    class OracleEnhancedJDBCConnection < OracleEnhancedConnection #:nodoc:

      attr_accessor :active
      alias :active? :active

      attr_accessor :auto_retry
      alias :auto_retry? :auto_retry
      @auto_retry = false

      def initialize(config)
        @active = true
        @config = config
        new_connection(@config)
      end

      # modified method to support JNDI connections
      def new_connection(config)
        username = nil

        if config[:jndi]
          jndi = config[:jndi].to_s
          ctx = javax.naming.InitialContext.new
          ds = nil

          # tomcat needs first lookup method, oc4j (and maybe other application servers) need second method
          begin
            env = ctx.lookup('java:/comp/env')
            ds = env.lookup(jndi)
          rescue
            ds = ctx.lookup(jndi)
          end

          # check if datasource supports pooled connections, otherwise use default
          if ds.respond_to?(:pooled_connection)
            @raw_connection = ds.pooled_connection
          else
            @raw_connection = ds.connection
          end

          # get Oracle JDBC connection when using DBCP in Tomcat or jBoss
          if @raw_connection.respond_to?(:getInnermostDelegate)
            @pooled_connection = @raw_connection
            @raw_connection = @raw_connection.innermost_delegate
          elsif @raw_connection.respond_to?(:getUnderlyingConnection)
            @pooled_connection = @raw_connection
            @raw_connection = @raw_connection.underlying_connection            
          end

          config[:driver] ||= @raw_connection.meta_data.connection.java_class.name
          username = @raw_connection.meta_data.user_name
        else
          # to_s needed if username, password or database is specified as number in database.yml file
          username = config[:username] && config[:username].to_s
          password = config[:password] && config[:password].to_s
          database = config[:database] && config[:database].to_s
          host, port = config[:host], config[:port]
          privilege = config[:privilege] && config[:privilege].to_s

          # connection using TNS alias
          if database && !host && !config[:url] && ENV['TNS_ADMIN']
            url = "jdbc:oracle:thin:@#{database || 'XE'}"
          else
            url = config[:url] || "jdbc:oracle:thin:@#{host || 'localhost'}:#{port || 1521}:#{database || 'XE'}"
          end

          prefetch_rows = config[:prefetch_rows] || 100
          # get session time_zone from configuration or from TZ environment variable
          time_zone = config[:time_zone] || ENV['TZ'] || java.util.TimeZone.default.getID

          properties = java.util.Properties.new
          properties.put("user", username)
          properties.put("password", password)
          properties.put("defaultRowPrefetch", "#{prefetch_rows}") if prefetch_rows
          properties.put("internal_logon", privilege) if privilege

          @raw_connection = java.sql.DriverManager.getConnection(url, properties)

          # Set session time zone to current time zone
          @raw_connection.setSessionTimeZone(time_zone)

          # Set default number of rows to prefetch
          # @raw_connection.setDefaultRowPrefetch(prefetch_rows) if prefetch_rows
        end

        cursor_sharing = config[:cursor_sharing] || 'force'
        exec "alter session set cursor_sharing = #{cursor_sharing}"

        # Initialize NLS parameters
        OracleEnhancedAdapter::DEFAULT_NLS_PARAMETERS.each do |key, default_value|
          value = config[key] || ENV[key.to_s.upcase] || default_value
          if value
            exec "alter session set #{key} = '#{value}'"
          end
        end

        self.autocommit = true

        # default schema owner
        @owner = username.upcase unless username.nil?

        @raw_connection
      end

      def logoff
        @active = false
        if defined?(@pooled_connection)
          @pooled_connection.close
        else
          @raw_connection.close
        end
        true
      rescue
        false
      end

      def commit
        @raw_connection.commit
      end

      def rollback
        @raw_connection.rollback
      end

      def autocommit?
        @raw_connection.getAutoCommit
      end

      def autocommit=(value)
        @raw_connection.setAutoCommit(value)
      end

      # Checks connection, returns true if active. Note that ping actively
      # checks the connection, while #active? simply returns the last
      # known state.
      def ping
        exec_no_retry("select 1 from dual")
        @active = true
      rescue NativeException => e
        @active = false
        if e.message =~ /^java\.sql\.SQL(Recoverable)?Exception/
          raise OracleEnhancedConnectionException, e.message
        else
          raise
        end
      end

      # Resets connection, by logging off and creating a new connection.
      def reset!
        logoff rescue nil
        begin
          new_connection(@config)
          @active = true
        rescue NativeException => e
          @active = false
          if e.message =~ /^java\.sql\.SQL(Recoverable)?Exception/
            raise OracleEnhancedConnectionException, e.message
          else
            raise
          end
        end
      end

      # mark connection as dead if connection lost
      def with_retry(&block)
        should_retry = auto_retry? && autocommit?
        begin
          yield if block_given?
        rescue NativeException => e
          raise unless e.message =~ /^java\.sql\.SQL(Recoverable)?Exception: (Closed Connection|Io exception:|No more data to read from socket)/
          @active = false
          raise unless should_retry
          should_retry = false
          reset! rescue nil
          retry
        end
      end

      def exec(sql)
        with_retry do
          exec_no_retry(sql)
        end
      end

      def exec_no_retry(sql)
        case sql
        when /\A\s*(UPDATE|INSERT|DELETE)/i
          s = @raw_connection.prepareStatement(sql)
          s.executeUpdate
        # it is safer for CREATE and DROP statements not to use PreparedStatement
        # as it does not allow creation of triggers with :NEW in their definition
        when /\A\s*(CREATE|DROP)/i
          s = @raw_connection.createStatement()
          # this disables SQL92 syntax processing of {...} which can result in statement execution errors
          # if sql contains {...} in strings or comments
          s.setEscapeProcessing(false)
          s.execute(sql)
          true
        else
          s = @raw_connection.prepareStatement(sql)
          s.execute
          true
        end
      ensure
        s.close rescue nil
      end

      def returning_clause(quoted_pk)
        " RETURNING #{quoted_pk} INTO ?"
      end

      # execute sql with RETURNING ... INTO :insert_id
      # and return :insert_id value
      def exec_with_returning(sql)
        with_retry do
          begin
            # it will always be INSERT statement

            # TODO: need to investigate why PreparedStatement is giving strange exception "Protocol violation"
            # s = @raw_connection.prepareStatement(sql)
            # s.registerReturnParameter(1, ::Java::oracle.jdbc.OracleTypes::NUMBER)
            # count = s.executeUpdate
            # if count > 0
            #   rs = s.getReturnResultSet
            #   if rs.next
            #     # Assuming that primary key will not be larger as long max value
            #     insert_id = rs.getLong(1)
            #     rs.wasNull ? nil : insert_id
            #   else
            #     nil
            #   end
            # else
            #   nil
            # end
            
            # Workaround with CallableStatement
            s = @raw_connection.prepareCall("BEGIN #{sql}; END;")
            s.registerOutParameter(1, java.sql.Types::BIGINT)
            s.execute
            insert_id = s.getLong(1)
            s.wasNull ? nil : insert_id
          ensure
            # rs.close rescue nil
            s.close rescue nil
          end
        end
      end

      def prepare(sql)
        Cursor.new(self, @raw_connection.prepareStatement(sql))
      end

      class Cursor
        def initialize(connection, raw_statement)
          @connection = connection
          @raw_statement = raw_statement
        end

        def bind_param(position, value)
          java_value = ruby_to_java_value(value)
          case value
          when Integer
            @raw_statement.setInt(position, java_value)
          when Float
            @raw_statement.setFloat(position, java_value)
          when BigDecimal
            @raw_statement.setBigDecimal(position, java_value)
          when String
            @raw_statement.setString(position, java_value)
          when Date, DateTime
            @raw_statement.setDATE(position, java_value)
          when Time
            @raw_statement.setTimestamp(position, java_value)
          when NilClass
            # TODO: currently nil is always bound as NULL with VARCHAR type.
            # When nils will actually be used by ActiveRecord as bound parameters
            # then need to pass actual column type.
            @raw_statement.setNull(position, java.sql.Types::VARCHAR)
          else
            raise ArgumentError, "Don't know how to bind variable with type #{value.class}"
          end
        end

        def exec
          @raw_result_set = @raw_statement.executeQuery
          get_metadata
          true
        end

        def get_metadata
          metadata = @raw_result_set.getMetaData
          column_count = metadata.getColumnCount
          @column_names = (1..column_count).map{|i| metadata.getColumnName(i)}
          @column_types = (1..column_count).map{|i| metadata.getColumnTypeName(i).to_sym}
        end

        def get_col_names
          @column_names
        end

        def fetch(options={})
          if @raw_result_set.next
            get_lob_value = options[:get_lob_value]
            row_values = []
            @column_types.each_with_index do |column_type, i|
              row_values <<
                @connection.get_ruby_value_from_result_set(@raw_result_set, i+1, column_type, get_lob_value)
            end
            row_values
          else
            @raw_result_set.close
            nil
          end
        end

        def close
          @raw_statement.close
        end

        private

        def ruby_to_java_value(value)
          case value
          when Fixnum, String, Float
            value
          when BigDecimal
            java.math.BigDecimal.new(value.to_s)
          when Date, DateTime
            Java::oracle.sql.DATE.new(value.strftime("%Y-%m-%d %H:%M:%S"))
          when Time
            Java::java.sql.Timestamp.new(value.year-1900, value.month-1, value.day, value.hour, value.min, value.sec, value.usec * 1000)
          else
            value
          end
        end

      end

      def select(sql, name = nil, return_column_names = false)
        with_retry do
          select_no_retry(sql, name, return_column_names)
        end
      end

      def select_no_retry(sql, name = nil, return_column_names = false)
        stmt = @raw_connection.prepareStatement(sql)
        rset = stmt.executeQuery

        # Reuse the same hash for all rows
        column_hash = {}

        metadata = rset.getMetaData
        column_count = metadata.getColumnCount

        cols_types_index = (1..column_count).map do |i|
          col_name = oracle_downcase(metadata.getColumnName(i))
          next if col_name == 'raw_rnum_'
          column_hash[col_name] = nil
          [col_name, metadata.getColumnTypeName(i).to_sym, i]
        end
        cols_types_index.delete(nil)

        rows = []
        get_lob_value = !(name == 'Writable Large Object')

        while rset.next
          hash = column_hash.dup
          cols_types_index.each do |col, column_type, i|
            hash[col] = get_ruby_value_from_result_set(rset, i, column_type, get_lob_value)
          end
          rows << hash
        end

        return_column_names ? [rows, cols_types_index.map(&:first)] : rows
      ensure
        rset.close rescue nil
        stmt.close rescue nil
      end

      def write_lob(lob, value, is_binary = false)
        if is_binary
          lob.setBytes(1, value.to_java_bytes)
        else
          lob.setString(1,value)
        end
      end

      # Return NativeException / java.sql.SQLException error code
      def error_code(exception)
        case exception
        when NativeException
          exception.cause.getErrorCode
        else
          nil
        end
      end

      def get_ruby_value_from_result_set(rset, i, type_name, get_lob_value = true)
        case type_name
        when :NUMBER
          d = rset.getNUMBER(i)
          if d.nil?
            nil
          elsif d.isInt
            Integer(d.stringValue)
          else
            BigDecimal.new(d.stringValue)
          end
        when :VARCHAR2, :CHAR, :LONG
          rset.getString(i)
        when :DATE
          if dt = rset.getDATE(i)
            d = dt.dateValue
            t = dt.timeValue
            if OracleEnhancedAdapter.emulate_dates && t.hours == 0 && t.minutes == 0 && t.seconds == 0
              Date.new(d.year + 1900, d.month + 1, d.date)
            else
              Time.send(Base.default_timezone, d.year + 1900, d.month + 1, d.date, t.hours, t.minutes, t.seconds)
            end
          else
            nil
          end
        when :TIMESTAMP, :TIMESTAMPTZ, :TIMESTAMPLTZ
          ts = rset.getTimestamp(i)
          ts && Time.send(Base.default_timezone, ts.year + 1900, ts.month + 1, ts.date, ts.hours, ts.minutes, ts.seconds,
            ts.nanos / 1000)
        when :CLOB
          get_lob_value ? lob_to_ruby_value(rset.getClob(i)) : rset.getClob(i)
        when :BLOB
          get_lob_value ? lob_to_ruby_value(rset.getBlob(i)) : rset.getBlob(i)
        else
          nil
        end
      end

      private

      def lob_to_ruby_value(val)
        case val
        when ::Java::OracleSql::CLOB
          if val.isEmptyLob
            nil
          else
            val.getSubString(1, val.length)
          end
        when ::Java::OracleSql::BLOB
          if val.isEmptyLob
            nil
          else
            String.from_java_bytes(val.getBytes(1, val.length))
          end
        end
      end

    end

  end
end
