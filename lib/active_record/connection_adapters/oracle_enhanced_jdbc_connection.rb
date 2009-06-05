begin
  require "java"
  require "jruby"
  # Adds JRuby classloader to current thread classloader - as a result ojdbc14.jar should not be in $JRUBY_HOME/lib
  java.lang.Thread.currentThread.setContextClassLoader(JRuby.runtime.jruby_class_loader)

  ojdbc_jar = "ojdbc14.jar"
  if ojdbc_jar_path = ENV["PATH"].split(/[:;]/).find{|d| File.exists?(File.join(d,ojdbc_jar))}
    require File.join(ojdbc_jar_path,ojdbc_jar)
  end
  # import java.sql.Statement
  # import java.sql.Connection
  # import java.sql.SQLException
  # import java.sql.Types
  # import java.sql.DriverManager
  java.sql.DriverManager.registerDriver Java::oracle.jdbc.driver.OracleDriver.new

rescue LoadError, NameError
  # JDBC driver is unavailable.
  error_message = "ERROR: ActiveRecord oracle_enhanced adapter could not load Oracle JDBC driver. "+
                  "Please install ojdbc14.jar library."
  if defined?(RAILS_DEFAULT_LOGGER)
    RAILS_DEFAULT_LOGGER.error error_message
  else
    STDERR.puts error_message
  end
  raise LoadError
end


module ActiveRecord
  module ConnectionAdapters

    # JDBC database interface for JRuby
    class OracleEnhancedJDBCConnection < OracleEnhancedConnection

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

      def new_connection(config)
        username, password, database = config[:username].to_s, config[:password].to_s, config[:database].to_s
        privilege = config[:privilege] && config[:privilege].to_s
        host, port = config[:host], config[:port]

        url = config[:url] || "jdbc:oracle:thin:@#{host || 'localhost'}:#{port || 1521}:#{database || 'XE'}"

        prefetch_rows = config[:prefetch_rows] || 100
        cursor_sharing = config[:cursor_sharing] || 'similar'

        properties = java.util.Properties.new
        properties.put("user", username)
        properties.put("password", password)
        properties.put("defaultRowPrefetch", "#{prefetch_rows}") if prefetch_rows
        properties.put("internal_logon", privilege) if privilege

        @raw_connection = java.sql.DriverManager.getConnection(url, properties)
        exec %q{alter session set nls_date_format = 'YYYY-MM-DD HH24:MI:SS'}
        exec %q{alter session set nls_timestamp_format = 'YYYY-MM-DD HH24:MI:SS'} # rescue nil
        exec "alter session set cursor_sharing = #{cursor_sharing}" # rescue nil
        self.autocommit = true
        
        # Set session time zone to current time zone
        @raw_connection.setSessionTimeZone(java.util.TimeZone.default.getID)
        
        # Set default number of rows to prefetch
        # @raw_connection.setDefaultRowPrefetch(prefetch_rows) if prefetch_rows
        
        # default schema owner
        @owner = username.upcase
        
        @raw_connection
      end

      
      def logoff
        @active = false
        @raw_connection.close
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
        if e.message =~ /^java\.sql\.SQLException/
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
          if e.message =~ /^java\.sql\.SQLException/
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
          raise unless e.message =~ /^java\.sql\.SQLException: (Closed Connection|Io exception:|No more data to read from socket)/
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
        cs = @raw_connection.prepareCall(sql)
        case sql
        when /\A\s*UPDATE/i, /\A\s*INSERT/i, /\A\s*DELETE/i
          cs.executeUpdate
        else
          cs.execute
          true
        end
      ensure
        cs.close rescue nil        
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

      def describe(name)
        real_name = OracleEnhancedAdapter.valid_table_name?(name) ? name.to_s.upcase : name.to_s
        if real_name.include?('.')
          table_owner, table_name = real_name.split('.')
        else
          table_owner, table_name = @owner, real_name
        end
        sql = <<-SQL
          SELECT owner, table_name, 'TABLE' name_type
          FROM all_tables
          WHERE owner = '#{table_owner}'
            AND table_name = '#{table_name}'
          UNION ALL
          SELECT owner, view_name table_name, 'VIEW' name_type
          FROM all_views
          WHERE owner = '#{table_owner}'
            AND view_name = '#{table_name}'
          UNION ALL
          SELECT table_owner, table_name, 'SYNONYM' name_type
          FROM all_synonyms
          WHERE owner = '#{table_owner}'
            AND synonym_name = '#{table_name}'
          UNION ALL
          SELECT table_owner, table_name, 'SYNONYM' name_type
          FROM all_synonyms
          WHERE owner = 'PUBLIC'
            AND synonym_name = '#{real_name}'
        SQL
        if result = select_one(sql)
          case result['name_type']
          when 'SYNONYM'
            describe("#{result['owner']}.#{result['table_name']}")
          else
            [result['owner'], result['table_name']]
          end
        else
          raise OracleEnhancedConnectionException, %Q{"DESC #{name}" failed; does it exist?}
        end
      end
      

      private

      # def prepare_statement(sql)
      #   @raw_connection.prepareStatement(sql)
      # end

      # def prepare_call(sql, *bindvars)
      #   @raw_connection.prepareCall(sql)
      # end

      def get_ruby_value_from_result_set(rset, i, type_name, get_lob_value = true)
        case type_name
        when :NUMBER
          # d = rset.getBigDecimal(i)
          # if d.nil?
          #   nil
          # elsif d.scale == 0
          #   d.toBigInteger+0
          # else
          #   # Is there better way how to convert Java BigDecimal to Ruby BigDecimal?
          #   d.toString.to_d
          # end
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
