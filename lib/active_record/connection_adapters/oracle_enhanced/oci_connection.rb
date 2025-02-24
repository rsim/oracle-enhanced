# frozen_string_literal: true

require "delegate"

begin
  require "oci8"
rescue LoadError => e
  # OCI8 driver is unavailable or failed to load a required library.
  raise LoadError, "ERROR: '#{e.message}'. "\
    "ActiveRecord oracle_enhanced adapter could not load ruby-oci8 library. "\
    "You may need install ruby-oci8 gem."
end

# check ruby-oci8 version
required_oci8_version = [2, 2, 4]
oci8_version_ints = OCI8::VERSION.scan(/\d+/).map { |s| s.to_i }
if (oci8_version_ints <=> required_oci8_version) < 0
  $stderr.puts <<~EOS
    "ERROR: ruby-oci8 version #{OCI8::VERSION} is too old. Please install ruby-oci8 version #{required_oci8_version.join('.')} or later."
  EOS

  exit!
end

module ActiveRecord
  module ConnectionAdapters
    # OCI database interface for MRI
    module OracleEnhanced
      class OCIConnection < OracleEnhanced::Connection # :nodoc:
        def initialize(config)
          @raw_connection = OCI8EnhancedAutoRecover.new(config, OracleEnhancedOCIFactory)
          # default schema owner
          @owner = config[:schema]
          @owner ||= config[:username]
          @owner = @owner.to_s.upcase
        end

        def raw_oci_connection
          if @raw_connection.is_a? OCI8
            @raw_connection
          # ActiveRecord Oracle enhanced adapter puts OCI8EnhancedAutoRecover wrapper around OCI8
          # in this case we need to pass original OCI8 connection
          else
            @raw_connection.instance_variable_get(:@raw_connection)
          end
        end

        def auto_retry
          @raw_connection.auto_retry if @raw_connection
        end

        def auto_retry=(value)
          @raw_connection.auto_retry = value if @raw_connection
        end

        def logoff
          @raw_connection.logoff
          @raw_connection.active = false
        end

        def commit
          @raw_connection.commit
        end

        def rollback
          @raw_connection.rollback
        end

        def autocommit?
          @raw_connection.autocommit?
        end

        def autocommit=(value)
          @raw_connection.autocommit = value
        end

        # Checks connection, returns true if active. Note that ping actively
        # checks the connection, while #active? simply returns the last
        # known state.
        def ping
          @raw_connection.ping
        rescue OCIException => e
          raise OracleEnhanced::ConnectionException, e.message
        end

        def active?
          @raw_connection.active?
        end

        def reset
          @raw_connection.reset
        end

        def reset!
          @raw_connection.reset!
        rescue OCIException => e
          raise OracleEnhanced::ConnectionException, e.message
        end

        def exec(sql, *bindvars, allow_retry: false, &block)
          with_retry(allow_retry: allow_retry) { @raw_connection.exec(sql, *bindvars, &block) }
        end

        def with_retry(allow_retry: false, &block)
          @raw_connection.with_retry(allow_retry: allow_retry, &block)
        end

        def prepare(sql)
          Cursor.new(self, @raw_connection.parse(sql))
        end

        class Cursor
          def initialize(connection, raw_cursor)
            @raw_connection = connection
            @raw_cursor = raw_cursor
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
            when Type::OracleEnhanced::Raw
              @raw_cursor.bind_param(position, OracleEnhanced::Quoting.encode_raw(value))
            when ActiveModel::Type::Decimal
              @raw_cursor.bind_param(position, BigDecimal(value.to_s))
            when Type::OracleEnhanced::CharacterString::Data
              @raw_cursor.bind_param(position, value.to_character_str)
            when NilClass
              @raw_cursor.bind_param(position, nil, String)
            else
              @raw_cursor.bind_param(position, value)
            end
          end

          def bind_returning_param(position, bind_type)
            @raw_cursor.bind_param(position, nil, bind_type)
          end

          def exec
            @raw_cursor.exec
          end

          def exec_update
            @raw_cursor.exec
          end

          def get_col_names
            @raw_cursor.get_col_names
          end

          def row_count
            @raw_cursor.row_count
          end

          def fetch(options = {})
            if row = @raw_cursor.fetch
              get_lob_value = options[:get_lob_value]
              col_index = 0
              row.map do |col|
                col_value = @raw_connection.typecast_result_value(col, get_lob_value)
                col_metadata = @raw_cursor.column_metadata.fetch(col_index)
                if !col_metadata.nil?
                  key = col_metadata.data_type
                  case key.to_s.downcase
                  when "char"
                    col_value = col.to_s.rstrip
                  end
                end
                col_index = col_index + 1
                col_value
              end
            end
          end

          def get_returning_param(position, type)
            @raw_cursor[position]
          end

          def close
            @raw_cursor.close
          end
        end

        def select(sql, name = nil, return_column_names = false)
          cursor = @raw_connection.exec(sql)
          cols = []
          # Ignore raw_rnum_ which is used to simulate LIMIT and OFFSET
          cursor.get_col_names.each do |col_name|
            col_name = _oracle_downcase(col_name)
            cols << col_name unless col_name == "raw_rnum_"
          end
          # Reuse the same hash for all rows
          column_hash = {}
          cols.each { |c| column_hash[c] = nil }
          rows = []
          get_lob_value = !(name == "Writable Large Object")

          while row = cursor.fetch
            hash = column_hash.dup

            cols.each_with_index do |col, i|
              col_value = typecast_result_value(row[i], get_lob_value)
              col_metadata = cursor.column_metadata.fetch(i)
              if !col_metadata.nil?
                key = col_metadata.data_type
                case key.to_s.downcase
                when "char"
                  col_value = col_value.to_s.rstrip
                end
              end
              hash[col] = col_value
            end

            rows << hash
          end

          return_column_names ? [rows, cols] : rows
        ensure
          cursor.close if cursor
        end

        def write_lob(lob, value, is_binary = false)
          lob.write value
        end

        def describe(name)
          super
        end

        # Return OCIError error code
        def error_code(exception)
          case exception
          when OCIError
            exception.code
          else
            nil
          end
        end

        def typecast_result_value(value, get_lob_value)
          case value
          when Integer
            value
          when String
            value
          when Float, BigDecimal
            # return Integer if value is integer (to avoid issues with _before_type_cast values for id attributes)
            value == (v_to_i = value.to_i) ? v_to_i : value
          when OCI8::LOB
            if get_lob_value
              data = value.read || ""     # if value.read returns nil, then we have an empty_clob() i.e. an empty string
              # In Ruby 1.9.1 always change encoding to ASCII-8BIT for binaries
              data.force_encoding("ASCII-8BIT") if data.respond_to?(:force_encoding) && value.is_a?(OCI8::BLOB)
              data
            else
              value
            end
          when Time, DateTime
            create_time_with_default_timezone(value)
          else
            value
          end
        end

        def database_version
          @database_version ||= (version = raw_connection.oracle_server_version) && [version.major, version.minor]
        end

      private
        def date_without_time?(value)
          case value
          when OraDate
            value.hour == 0 && value.minute == 0 && value.second == 0
          else
            value.hour == 0 && value.min == 0 && value.sec == 0
          end
        end

        def create_time_with_default_timezone(value)
          year, month, day, hour, min, sec, usec = case value
                                                   when Time
                                                     [value.year, value.month, value.day, value.hour, value.min, value.sec, value.usec]
                                                   when OraDate
                                                     [value.year, value.month, value.day, value.hour, value.minute, value.second, 0]
                                                   else
                                                     [value.year, value.month, value.day, value.hour, value.min, value.sec, 0]
          end
          # code from Time.time_with_datetime_fallback
          begin
            Time.send(ActiveRecord.default_timezone, year, month, day, hour, min, sec, usec)
          rescue
            offset = ActiveRecord.default_timezone.to_sym == :local ? ::DateTime.local_offset : 0
            ::DateTime.civil(year, month, day, hour, min, sec, offset)
          end
        end
      end

      # The OracleEnhancedOCIFactory factors out the code necessary to connect and
      # configure an Oracle/OCI connection.
      class OracleEnhancedOCIFactory # :nodoc:
        DEFAULT_TCP_KEEPALIVE_TIME = 600

        def self.new_connection(config)
          # to_s needed if username, password or database is specified as number in database.yml file
          username = config[:username] && config[:username].to_s
          password = config[:password] && config[:password].to_s
          database = config[:database] && config[:database].to_s
          schema = config[:schema] && config[:schema].to_s
          host, port = config[:host], config[:port]
          privilege = config[:privilege] && config[:privilege].to_sym
          async = config[:allow_concurrency]
          prefetch_rows = config[:prefetch_rows] || 100
          cursor_sharing = config[:cursor_sharing] || "force"
          # get session time_zone from configuration or from TZ environment variable
          time_zone = config[:time_zone] || ENV["TZ"]

          # using a connection string via DATABASE_URL
          connection_string = if host == "connection-string"
            database
          # connection using host, port and database name
          elsif host || port
            host ||= "localhost"
            host = "[#{host}]" if /^[^\[].*:/.match?(host)  # IPv6
            port ||= 1521
            database = "/#{database}" unless database.start_with?("/")
            "//#{host}:#{port}#{database}"
          # if no host is specified then assume that
          # database parameter is TNS alias or TNS connection string
          else
            database
          end

          OCI8.properties[:tcp_keepalive] = config[:tcp_keepalive] == false ? false : true
          begin
            OCI8.properties[:tcp_keepalive_time] = config[:tcp_keepalive_time] || DEFAULT_TCP_KEEPALIVE_TIME
          rescue NotImplementedError
          end

          conn = OCI8.new username, password, connection_string, privilege
          conn.autocommit = true
          conn.non_blocking = true if async
          conn.prefetch_rows = prefetch_rows
          conn.exec "alter session set cursor_sharing = #{cursor_sharing}" rescue nil if cursor_sharing
          if ActiveRecord.default_timezone == :local
            conn.exec "alter session set time_zone = '#{time_zone}'" unless time_zone.blank?
          elsif ActiveRecord.default_timezone == :utc
            conn.exec "alter session set time_zone = '+00:00'"
          end
          conn.exec "alter session set current_schema = #{schema}" unless schema.blank?

          # Initialize NLS parameters
          OracleEnhancedAdapter::DEFAULT_NLS_PARAMETERS.each do |key, default_value|
            value = config[key] || ENV[key.to_s.upcase] || default_value
            if value
              conn.exec "alter session set #{key} = '#{value}'"
            end
          end

          OracleEnhancedAdapter::FIXED_NLS_PARAMETERS.each do |key, value|
            conn.exec "alter session set #{key} = '#{value}'"
          end
          conn
        end
      end
    end
  end
end

# The OCI8AutoRecover class enhances the OCI8 driver with auto-recover and
# reset functionality. If a call to #exec fails, and autocommit is turned on
# (ie., we're not in the middle of a longer transaction), it will
# automatically reconnect and try again. If autocommit is turned off,
# this would be dangerous (as the earlier part of the implied transaction
# may have failed silently if the connection died) -- so instead the
# connection is marked as dead, to be reconnected on it's next use.
# :stopdoc:
class OCI8EnhancedAutoRecover < DelegateClass(OCI8) # :nodoc:
  attr_accessor :active # :nodoc:
  alias :active? :active # :nodoc:

  cattr_accessor :auto_retry
  class << self
    alias :auto_retry? :auto_retry # :nodoc:
  end
  @@auto_retry = false

  def initialize(config, factory) # :nodoc:
    @active = true
    @config = config
    @factory = factory
    @raw_connection = @factory.new_connection @config
    super @raw_connection
  end

  # Checks connection, returns true if active. Note that ping actively
  # checks the connection, while #active? simply returns the last
  # known state.
  def ping # :nodoc:
    @raw_connection.exec("select 1 from dual") { |r| nil }
    @active = true
  rescue
    @active = false
    raise
  end

  def reset
    # tentative
    reset!
  end

  # Resets connection, by logging off and creating a new connection.
  def reset! # :nodoc:
    logoff rescue nil
    begin
      @raw_connection = @factory.new_connection @config
      __setobj__ @raw_connection
      @active = true
    rescue
      @active = false
      raise
    end
  end

  # ORA-00028: your session has been killed
  # ORA-01012: not logged on
  # ORA-03113: end-of-file on communication channel
  # ORA-03114: not connected to ORACLE
  # ORA-03135: connection lost contact
  LOST_CONNECTION_ERROR_CODES = [ 28, 1012, 3113, 3114, 3135 ] # :nodoc:

  # Adds auto-recovery functionality.
  def with_retry(allow_retry: false) # :nodoc:
    should_retry = (allow_retry || self.class.auto_retry?) && autocommit?

    begin
      yield
    rescue OCIException => e
      raise unless e.is_a?(OCIError) && LOST_CONNECTION_ERROR_CODES.include?(e.code)
      @active = false
      raise unless should_retry
      should_retry = false
      reset! rescue nil
      retry
    end
  end

  def exec(sql, *bindvars, &block) # :nodoc:
    with_retry { @raw_connection.exec(sql, *bindvars, &block) }
  end
end
# :startdoc:
