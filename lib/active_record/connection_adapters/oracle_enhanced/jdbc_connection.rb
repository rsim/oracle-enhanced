# frozen_string_literal: true

begin
  require "java"
  require "jruby"

  # ojdbc7.jar or ojdbc6.jar file should be in application ./lib directory or in load path or in ENV['PATH']

  java_version = java.lang.System.getProperty("java.version")
  # Dropping Java SE 6(1.6) or older version without deprecation cycle.
  # Rails 5.0 already requires CRuby 2.2.2 or higher and JRuby 9.0 supporging CRuby 2.2 requires Java SE 7.
  if java_version < "1.7"
    raise "ERROR: Java SE 6 or older version is not supported. Upgrade Java version to Java SE 7 or higher"
  end

  # Oracle 11g client ojdbc6.jar is also compatible with Java 1.7
  # Oracle 12c Release 1 client provides ojdbc7.jar
  # Oracle 12c Release 2 client provides ojdbc8.jar
  # Oracle 21c provides ojdbc11.jar for Java 11 and above
  # Oracle 23c provides ojdbc17.jar for Java 17 and above
  ojdbc_jars = %w(ojdbc17.jar ojdbc11.jar ojdbc8.jar ojdbc7.jar ojdbc6.jar)

  if !ENV_JAVA["java.class.path"]&.match?(Regexp.new(ojdbc_jars.join("|")))
    # On Unix environment variable should be PATH, on Windows it is sometimes Path
    env_path = (ENV["PATH"] || ENV["Path"] || "").split(File::PATH_SEPARATOR)
    # Look for JDBC driver at first in lib subdirectory (application specific JDBC file version)
    # then in Ruby load path and finally in environment PATH
    ["./lib"].concat($LOAD_PATH).concat(env_path).detect do |dir|
      # check any compatible JDBC driver in the priority order
      ojdbc_jars.any? do |ojdbc_jar|
        if File.exist?(file_path = File.join(dir, ojdbc_jar))
          require file_path
          true
        end
      end
    end
  end

  ORACLE_DRIVER = Java::oracle.jdbc.OracleDriver.new
  java.sql.DriverManager.registerDriver ORACLE_DRIVER

  # set tns_admin property from TNS_ADMIN environment variable
  if !java.lang.System.get_property("oracle.net.tns_admin") && ENV["TNS_ADMIN"]
    java.lang.System.set_property("oracle.net.tns_admin", ENV["TNS_ADMIN"])
  end

rescue LoadError, NameError => e
  # JDBC driver is unavailable.
  raise LoadError, "ERROR: ActiveRecord oracle_enhanced adapter could not load Oracle JDBC driver. Please install #{ojdbc_jars.join(' or ') } library.\n#{e.class}:#{e.message}"
end

module ActiveRecord
  module ConnectionAdapters
    # JDBC database interface for JRuby
    module OracleEnhanced
      class JDBCConnection < OracleEnhanced::Connection # :nodoc:
        attr_accessor :active
        alias :active? :active

        attr_accessor :auto_retry
        alias :auto_retry? :auto_retry
        @auto_retry = false

        attr_reader :session_time_zone

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
              env = ctx.lookup("java:/comp/env")
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

            # Workaround FrozenError (can't modify frozen Hash):
            config = config.dup
            config[:driver] ||= @raw_connection.meta_data.connection.java_class.name
            username = @raw_connection.meta_data.user_name
          else
            # to_s needed if username, password or database is specified as number in database.yml file
            username = config[:username] && config[:username].to_s
            password = config[:password] && config[:password].to_s
            database = config[:database] && config[:database].to_s || "XE"
            host, port = config[:host], config[:port]
            privilege = config[:privilege] && config[:privilege].to_s

            # connection using TNS alias, or connection-string from DATABASE_URL
            using_tns_alias = !host && !config[:url] && ENV["TNS_ADMIN"]
            if database && (using_tns_alias || host == "connection-string")
              url = "jdbc:oracle:thin:@#{database}"
            else
              unless database.match?(/^(:|\/)/)
                # assume database is a SID if no colon or slash are supplied (backward-compatibility)
                database = "/#{database}"
              end
              url = config[:url] || "jdbc:oracle:thin:@//#{host || 'localhost'}:#{port || 1521}#{database}"
            end

            prefetch_rows = config[:prefetch_rows] || 100
            # get session time_zone from configuration or from TZ environment variable
            time_zone = config[:time_zone] || ENV["TZ"] || java.util.TimeZone.default.getID

            properties = java.util.Properties.new
            raise "username not set" unless username
            raise "password not set" unless password
            properties.put("user", username)
            properties.put("password", password)
            properties.put("defaultRowPrefetch", "#{prefetch_rows}") if prefetch_rows
            properties.put("internal_logon", privilege) if privilege

            if config[:jdbc_connect_properties] # arbitrary additional properties for JDBC connection
              raise "jdbc_connect_properties should contain an associative array / hash" unless config[:jdbc_connect_properties].is_a? Hash
              config[:jdbc_connect_properties].each do |key, value|
                properties.put(key, value)
              end
            end

            begin
              @raw_connection = java.sql.DriverManager.getConnection(url, properties)
            rescue
              # bypass DriverManager to work in cases where ojdbc*.jar
              # is added to the load path at runtime and not on the
              # system classpath
              @raw_connection = ORACLE_DRIVER.connect(url, properties)
            end

            # Set session time zone to current time zone
            if ActiveRecord.default_timezone == :local
              @raw_connection.setSessionTimeZone(time_zone)
              @session_time_zone = time_zone
            elsif ActiveRecord.default_timezone == :utc
              @raw_connection.setSessionTimeZone("UTC")
              @session_time_zone = "UTC"
            end

            if config[:jdbc_statement_cache_size]
              raise "Integer value expected for :jdbc_statement_cache_size" unless config[:jdbc_statement_cache_size].instance_of? Integer
              @raw_connection.setImplicitCachingEnabled(true)
              @raw_connection.setStatementCacheSize(config[:jdbc_statement_cache_size])
            end

            # Set default number of rows to prefetch
            # @raw_connection.setDefaultRowPrefetch(prefetch_rows) if prefetch_rows
          end

          cursor_sharing = config[:cursor_sharing] || "force"
          exec "alter session set cursor_sharing = #{cursor_sharing}" if cursor_sharing

          # Initialize NLS parameters
          OracleEnhancedAdapter::DEFAULT_NLS_PARAMETERS.each do |key, default_value|
            value = config[key] || ENV[key.to_s.upcase] || default_value
            if value
              exec "alter session set #{key} = '#{value}'"
            end
          end

          OracleEnhancedAdapter::FIXED_NLS_PARAMETERS.each do |key, value|
            exec "alter session set #{key} = '#{value}'"
          end

          self.autocommit = true

          schema = config[:schema] && config[:schema].to_s
          if schema.blank?
            # default schema owner
            @owner = username.upcase unless username.nil?
          else
            exec "alter session set current_schema = #{schema}"
            @owner = schema
          end

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
        rescue Java::JavaSql::SQLException => e
          @active = false
          raise OracleEnhanced::ConnectionException, e.message
        end

        # Resets connection, by logging off and creating a new connection.
        def reset
          reset!
        end

        def reset!
          logoff rescue nil
          begin
            new_connection(@config)
            @active = true
          rescue Java::JavaSql::SQLException => e
            @active = false
            raise OracleEnhanced::ConnectionException, e.message
          end
        end

        # mark connection as dead if connection lost
        def with_retry(allow_retry: false, &block)
          should_retry = (allow_retry || auto_retry?) && autocommit?
          begin
            yield if block_given?
          rescue Java::JavaSql::SQLException => e
            raise unless lost_connection?(e)
            @active = false
            raise unless should_retry
            should_retry = false
            reset! rescue nil
            retry
          end
        end

        def exec(sql, *bindvars, allow_retry: false)
          # The signature mirrors the OCI implementation for polymorphic
          # callers, but the JDBC path here has no bindvar handling. Fail
          # loudly rather than silently dropping values on the floor.
          raise ArgumentError, "JDBC exec does not support bindvars" unless bindvars.empty?
          with_retry(allow_retry: allow_retry) do
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

        def prepare(sql)
          # Use a plain Statement for DDL and PL/SQL blocks: PreparedStatement
          # interprets colons as bind-parameter markers which breaks trigger
          # definitions (:NEW/:OLD) and PL/SQL with named parameters.
          if /\A\s*(CREATE|DROP|BEGIN|DECLARE)/i.match?(sql)
            s = @raw_connection.createStatement()
            s.setEscapeProcessing(false)
            Cursor.new(self, s, sql)
          else
            Cursor.new(self, @raw_connection.prepareStatement(sql))
          end
        end

        def database_version
          @database_version ||= (md = raw_connection.getMetaData) && [md.getDatabaseMajorVersion, md.getDatabaseMinorVersion]
        end

        class Cursor
          def initialize(connection, raw_statement, exec_sql = nil)
            @raw_connection = connection
            @raw_statement = raw_statement
            @exec_sql = exec_sql  # non-nil for DDL/PL/SQL using createStatement
          end

          def bind_params(*bind_vars)
            index = 1
            bind_vars.flatten.each do |var|
              if Hash === var
                var.each { |key, val| bind_param key, val }
              else
                bind_param index, var
                index += 1
              end
            end
          end

          def bind_param(position, value)
            case value
            when Integer
              @raw_statement.setLong(position, value)
            when Float
              @raw_statement.setFloat(position, value)
            when BigDecimal
              @raw_statement.setBigDecimal(position, value)
            when Java::OracleSql::BLOB
              @raw_statement.setBlob(position, value)
            when Java::OracleSql::CLOB
              @raw_statement.setClob(position, value)
            when Java::OracleSql::NCLOB
              @raw_statement.setClob(position, value)
            when Type::OracleEnhanced::Raw
              @raw_statement.setString(position, OracleEnhanced::Quoting.encode_raw(value))
            when Type::OracleEnhanced::CharacterString::Data
              @raw_statement.setFixedCHAR(position, value.to_s)
            when String
              @raw_statement.setString(position, value)
            when Java::OracleSql::DATE
              @raw_statement.setDATE(position, value)
            when Java::JavaSql::Timestamp
              @raw_statement.setTimestamp(position, value)
            when Time
              new_value = java.sql.Timestamp.new(value.to_i * 1000)
              new_value.setNanos(value.nsec)
              # Oracle JDBC getTimestamp uses the session timezone, but setTimestamp
              # (without Calendar) uses the JVM default timezone. Pass a Calendar
              # matching the session timezone so both sides use the same reference.
              tz_id = @raw_connection.session_time_zone || java.util.TimeZone.default.getID
              cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone(tz_id))
              @raw_statement.setTimestamp(position, new_value, cal)
            when NilClass
              # TODO: currently nil is always bound as NULL with VARCHAR type.
              # When nils will actually be used by ActiveRecord as bound parameters
              # then need to pass actual column type.
              @raw_statement.setNull(position, java.sql.Types::VARCHAR)
            else
              raise ArgumentError, "Don't know how to bind variable with type #{value.class}"
            end
          end

          def bind_returning_param(position, bind_type)
            @returning_positions ||= []
            @returning_positions << position
            if bind_type == Integer
              @raw_statement.registerReturnParameter(position, java.sql.Types::BIGINT)
            end
          end

          def exec
            if @exec_sql
              # DDL / PL/SQL block executed via createStatement — never returns rows
              @raw_statement.execute(@exec_sql)
            elsif @raw_statement.execute
              # execute() returns true when the result is a ResultSet (SELECT)
              @raw_result_set = @raw_statement.getResultSet
            end
            true
          end

          def exec_update
            @raw_statement.executeUpdate
          end

          def metadata
            @metadata ||= @raw_result_set&.getMetaData
          end

          def column_types
            return [] unless @raw_result_set
            @column_types ||= (1..metadata.getColumnCount).map { |i| metadata.getColumnTypeName(i).to_sym }
          end

          def column_names
            return [] unless @raw_result_set
            @column_names ||= (1..metadata.getColumnCount).map { |i| metadata.getColumnName(i) }
          end
          alias :get_col_names :column_names

          def select_statement?
            !@raw_result_set.nil?
          end

          def row_count
            @raw_statement.getUpdateCount
          end

          def fetch(options = {})
            if @raw_result_set.next
              get_lob_value = options[:get_lob_value]
              row_values = []
              column_types.each_with_index do |column_type, i|
                row_values <<
                  @raw_connection.get_ruby_value_from_result_set(@raw_result_set, i + 1, column_type, get_lob_value)
              end
              row_values
            else
              @raw_result_set.close
              nil
            end
          end

          def get_returning_param(position, type)
            rs_position = @returning_positions.index(position) + 1
            rs = @raw_statement.getReturnResultSet
            if rs.next
              # Assuming that primary key will not be larger as long max value
              returning_id = rs.getLong(rs_position)
              rs.wasNull ? nil : returning_id
            else
              nil
            end
          end

          def close
            @raw_statement.close
          rescue Java::JavaSql::SQLException => e
            # Tolerate closing a statement whose underlying connection or
            # statement has already been torn down (typical after with_retry
            # has reset the connection). Re-raise anything else so genuine
            # driver/resource bugs surface.
            #
            #   ORA-17002 / ORA-17008 — connection already gone
            #     (see JDBC_LOST_CONNECTION_ERROR_CODES).
            #   ORA-17009 "Closed Statement" — the Statement handle is
            #     gone but the connection may still be alive. It is a
            #     cursor-local concern, not a lost-connection signal,
            #     which is why it is allowed here but excluded from
            #     JDBC_LOST_CONNECTION_ERROR_CODES / lost_connection?.
            raise unless JDBC_LOST_CONNECTION_ERROR_CODES.include?(e.getErrorCode) || e.getErrorCode == 17009
            nil
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
            col_name = _oracle_downcase(metadata.getColumnName(i))
            next if col_name == "raw_rnum_"
            column_hash[col_name] = nil
            [col_name, metadata.getColumnTypeName(i).to_sym, i]
          end
          cols_types_index.delete(nil)

          rows = []
          get_lob_value = !(name == "Writable Large Object")

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
            lob.setString(1, value)
          end
        end

        # To allow private method called from `JDBCConnection`
        def describe(name)
          super
        end

        # Return java.sql.SQLException error code
        def error_code(exception)
          case exception
          when Java::JavaSql::SQLException
            exception.getErrorCode
          else
            nil
          end
        end

        # Oracle JDBC driver (ojdbc) client-side error codes that indicate
        # the underlying connection is gone. Distinct from the shared
        # LOST_CONNECTION_ERROR_CODES, which lists Oracle Database server-
        # side ORA-NNNN codes — those can arrive via OCI as well, these
        # cannot: the 17NNN range is reserved for the JDBC driver itself
        # (the server never sends ORA-17NNN back).
        #   ORA-17002 Io exception       — network / socket failure
        #   ORA-17008 Closed Connection  — connection already closed
        #
        # ORA-17009 "Closed Statement" is deliberately NOT listed here:
        # it signals that only a stale Statement handle is gone while the
        # connection itself may still be alive, so lost_connection? must
        # not return true for it (doing so would discard a live session).
        # Cursor#close tolerates 17009 separately as a cursor-local
        # concern.
        JDBC_LOST_CONNECTION_ERROR_CODES = [17002, 17008]

        # Fallback for older ojdbc that surfaces disconnects with
        # SQLException#getErrorCode == 0 and no ORA-NNNNN prefix in the
        # message. ojdbc17+ produces proper error codes handled via the
        # *_ERROR_CODES lists above.
        LOST_CONNECTION_MESSAGE = /\A(Closed Connection|Io exception:|No more data to read from socket|IO Error:)/

        def lost_connection?(exception)
          return false unless exception.is_a?(Java::JavaSql::SQLException)
          code = exception.getErrorCode
          LOST_CONNECTION_ERROR_CODES.include?(code) ||
            JDBC_LOST_CONNECTION_ERROR_CODES.include?(code) ||
            LOST_CONNECTION_MESSAGE.match?(exception.message)
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
              BigDecimal(d.stringValue)
            end
          when :BINARY_FLOAT
            rset.getFloat(i)
          when :VARCHAR2, :LONG, :NVARCHAR2
            rset.getString(i)
          when :CHAR, :NCHAR
            char_str = rset.getString(i)
            if !char_str.nil?
              char_str.rstrip
            end
          when :DATE
            if dt = rset.getDATE(i)
              d = dt.dateValue
              t = dt.timeValue
              Time.send(ActiveRecord.default_timezone, d.year + 1900, d.month + 1, d.date, t.hours, t.minutes, t.seconds)
            else
              nil
            end
          when :TIMESTAMP
            # Oracle JDBC getTimestamp for plain TIMESTAMP uses the JVM default timezone,
            # but we store values using the session timezone. Pass a matching Calendar so
            # the driver interprets the stored wall-clock value in the session timezone.
            tz_id = @session_time_zone || java.util.TimeZone.default.getID
            cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone(tz_id))
            ts = rset.getTimestamp(i, cal)
            if ts
              instant = ts.toInstant
              t = Time.at(instant.getEpochSecond, instant.getNano, :nanosecond)
              ActiveRecord.default_timezone == :utc ? t.utc : t.localtime
            end
          when :TIMESTAMPTZ, :TIMESTAMPLTZ, :"TIMESTAMP WITH TIME ZONE", :"TIMESTAMP WITH LOCAL TIME ZONE"
            # TIMESTAMPTZ/TIMESTAMPLTZ include timezone info so getTimestamp returns
            # the correct UTC epoch without needing a Calendar.
            ts = rset.getTimestamp(i)
            if ts
              instant = ts.toInstant
              t = Time.at(instant.getEpochSecond, instant.getNano, :nanosecond)
              ActiveRecord.default_timezone == :utc ? t.utc : t.localtime
            end
          when :CLOB
            get_lob_value ? lob_to_ruby_value(rset.getClob(i)) : rset.getClob(i)
          when :NCLOB
            get_lob_value ? lob_to_ruby_value(rset.getClob(i)) : rset.getClob(i)
          when :BLOB
            get_lob_value ? lob_to_ruby_value(rset.getBlob(i)) : rset.getBlob(i)
          when :RAW
            raw_value = rset.getRAW(i)
            raw_value && raw_value.getBytes.to_a.pack("C*")
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
          when ::Java::OracleSql::NCLOB
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
end
