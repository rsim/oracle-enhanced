# -*- coding: utf-8 -*-
# oracle_enhanced_adapter.rb -- ActiveRecord adapter for Oracle 8i, 9i, 10g, 11g
#
# Authors or original oracle_adapter: Graham Jenkins, Michael Schoen
#
# Current maintainer: Raimonds Simanovskis (http://blog.rayapps.com)
#
#########################################################################
#
# See History.txt for changes added to original oracle_adapter.rb
#
#########################################################################
#
# From original oracle_adapter.rb:
#
# Implementation notes:
# 1. Redefines (safely) a method in ActiveRecord to make it possible to
#    implement an autonumbering solution for Oracle.
# 2. The OCI8 driver is patched to properly handle values for LONG and
#    TIMESTAMP columns. The driver-author has indicated that a future
#    release of the driver will obviate this patch.
# 3. LOB support is implemented through an after_save callback.
# 4. Oracle does not offer native LIMIT and OFFSET options; this
#    functionality is mimiced through the use of nested selects.
#    See http://asktom.oracle.com/pls/ask/f?p=4950:8:::::F4950_P8_DISPLAYID:127412348064
#
# Do what you want with this code, at your own peril, but if any
# significant portion of my code remains then please acknowledge my
# contribution.
# portions Copyright 2005 Graham Jenkins

require 'active_record/connection_adapters/abstract_adapter'

require 'active_record/connection_adapters/oracle_enhanced_connection'

require 'digest/sha1'

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects.
    def self.oracle_enhanced_connection(config) #:nodoc:
      if config[:emulate_oracle_adapter] == true
        # allows the enhanced adapter to look like the OracleAdapter. Useful to pick up
        # conditionals in the rails activerecord test suite
        require 'active_record/connection_adapters/emulation/oracle_adapter'
        ConnectionAdapters::OracleAdapter.new(
          ConnectionAdapters::OracleEnhancedConnection.create(config), logger)
      else
        ConnectionAdapters::OracleEnhancedAdapter.new(
          ConnectionAdapters::OracleEnhancedConnection.create(config), logger)
      end
    end

    # Specify table columns which should be ignored by ActiveRecord, e.g.:
    # 
    #   ignore_table_columns :attribute1, :attribute2
    def self.ignore_table_columns(*args)
      connection.ignore_table_columns(table_name,*args)
    end

    # Specify which table columns should be typecasted to Date (without time), e.g.:
    # 
    #   set_date_columns :created_on, :updated_on
    def self.set_date_columns(*args)
      connection.set_type_for_columns(table_name,:date,*args)
    end

    # Specify which table columns should be typecasted to Time (or DateTime), e.g.:
    # 
    #   set_datetime_columns :created_date, :updated_date
    def self.set_datetime_columns(*args)
      connection.set_type_for_columns(table_name,:datetime,*args)
    end

    # Specify which table columns should be typecasted to boolean values +true+ or +false+, e.g.:
    # 
    #   set_boolean_columns :is_valid, :is_completed
    def self.set_boolean_columns(*args)
      connection.set_type_for_columns(table_name,:boolean,*args)
    end

    # Specify which table columns should be typecasted to integer values.
    # Might be useful to force NUMBER(1) column to be integer and not boolean, or force NUMBER column without
    # scale to be retrieved as integer and not decimal. Example:
    # 
    #   set_integer_columns :version_number, :object_identifier
    def self.set_integer_columns(*args)
      connection.set_type_for_columns(table_name,:integer,*args)
    end

    # Specify which table columns should be typecasted to string values.
    # Might be useful to specify that columns should be string even if its name matches boolean column criteria.
    # 
    #   set_integer_columns :active_flag
    def self.set_string_columns(*args)
      connection.set_type_for_columns(table_name,:string,*args)
    end

    # After setting large objects to empty, select the OCI8::LOB
    # and write back the data.
    after_save :enhanced_write_lobs
    def enhanced_write_lobs #:nodoc:
      if connection.is_a?(ConnectionAdapters::OracleEnhancedAdapter) &&
          !(self.class.custom_create_method || self.class.custom_update_method)
        connection.write_lobs(self.class.table_name, self.class, attributes)
      end
    end
    private :enhanced_write_lobs
    
    class << self
      # patch ORDER BY to work with LOBs
      def add_order_with_lobs!(sql, order, scope = :auto)
        if connection.is_a?(ConnectionAdapters::OracleEnhancedAdapter)
          order = connection.lob_order_by_expression(self, order) if order
          
          orig_scope = scope
          scope = scope(:find) if :auto == scope
          if scope
            new_scope_order = connection.lob_order_by_expression(self, scope[:order])
            if new_scope_order != scope[:order]
              scope = scope.merge(:order => new_scope_order)
            else
              scope = orig_scope
            end
          end
        end
        add_order_without_lobs!(sql, order, scope = :auto)
      end
      private :add_order_with_lobs!
      #:stopdoc:
      alias_method :add_order_without_lobs!, :add_order!
      alias_method :add_order!, :add_order_with_lobs!
      #:startdoc:
    end
    
    # Get table comment from schema definition.
    def self.table_comment
      connection.table_comment(self.table_name)
    end
  end


  module ConnectionAdapters #:nodoc:
    class OracleEnhancedColumn < Column

      attr_reader :table_name, :forced_column_type #:nodoc:
      
      def initialize(name, default, sql_type = nil, null = true, table_name = nil, forced_column_type = nil) #:nodoc:
        @table_name = table_name
        @forced_column_type = forced_column_type
        super(name, default, sql_type, null)
      end

      def type_cast(value) #:nodoc:
        return guess_date_or_time(value) if type == :datetime && OracleEnhancedAdapter.emulate_dates
        super
      end

      # convert something to a boolean
      # added y as boolean value
      def self.value_to_boolean(value) #:nodoc:
        if value == true || value == false
          value
        elsif value.is_a?(String) && value.blank?
          nil
        else
          %w(true t 1 y +).include?(value.to_s.downcase)
        end
      end

      # convert Time or DateTime value to Date for :date columns
      def self.string_to_date(string) #:nodoc:
        return string.to_date if string.is_a?(Time) || string.is_a?(DateTime)
        super
      end

      # convert Date value to Time for :datetime columns
      def self.string_to_time(string) #:nodoc:
        return string.to_time if string.is_a?(Date) && !OracleEnhancedAdapter.emulate_dates
        super
      end

      # Get column comment from schema definition.
      # Will work only if using default ActiveRecord connection.
      def comment
        ActiveRecord::Base.connection.column_comment(@table_name, name)
      end
      
      private
      def simplified_type(field_type)
        forced_column_type ||
        case field_type
          when /decimal|numeric|number/i
            return :boolean if OracleEnhancedAdapter.emulate_booleans && field_type == 'NUMBER(1)'
            return :integer if extract_scale(field_type) == 0
            # if column name is ID or ends with _ID
            return :integer if OracleEnhancedAdapter.emulate_integers_by_column_name && OracleEnhancedAdapter.is_integer_column?(name, table_name)
            :decimal
          when /char/i
            return :boolean if OracleEnhancedAdapter.emulate_booleans_from_strings &&
                               OracleEnhancedAdapter.is_boolean_column?(name, field_type, table_name)
            :string
          when /date/i
            forced_column_type ||
            (:date if OracleEnhancedAdapter.emulate_dates_by_column_name && OracleEnhancedAdapter.is_date_column?(name, table_name)) ||
            :datetime
          when /timestamp/i then :timestamp
          when /time/i then :datetime
          else super
        end
      end

      def guess_date_or_time(value)
        value.respond_to?(:hour) && (value.hour == 0 and value.min == 0 and value.sec == 0) ?
          Date.new(value.year, value.month, value.day) : value
      end
      
      class << self
        protected

        def fallback_string_to_date(string) #:nodoc:
          if OracleEnhancedAdapter.string_to_date_format || OracleEnhancedAdapter.string_to_time_format
            return (string_to_date_or_time_using_format(string).to_date rescue super)
          end
          super
        end

        def fallback_string_to_time(string) #:nodoc:
          if OracleEnhancedAdapter.string_to_time_format || OracleEnhancedAdapter.string_to_date_format
            return (string_to_date_or_time_using_format(string).to_time rescue super)
          end
          super
        end

        def string_to_date_or_time_using_format(string) #:nodoc:
          if OracleEnhancedAdapter.string_to_time_format && dt=Date._strptime(string, OracleEnhancedAdapter.string_to_time_format)
            return Time.mktime(*dt.values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday))
          end
          DateTime.strptime(string, OracleEnhancedAdapter.string_to_date_format)
        end
        
      end
    end


    # Oracle enhanced adapter will work with both
    # Ruby 1.8/1.9 ruby-oci8 gem (which provides interface to Oracle OCI client)
    # or with JRuby and Oracle JDBC driver.
    # 
    # It should work with Oracle 9i, 10g and 11g databases.
    # Limited set of functionality should work on Oracle 8i as well but several features
    # rely on newer functionality in Oracle database.
    #
    # Usage notes:
    # * Key generation assumes a "${table_name}_seq" sequence is available
    #   for all tables; the sequence name can be changed using
    #   ActiveRecord::Base.set_sequence_name. When using Migrations, these
    #   sequences are created automatically.
    #   Use set_sequence_name :autogenerated with legacy tables that have
    #   triggers that populate primary keys automatically.
    # * Oracle uses DATE or TIMESTAMP datatypes for both dates and times.
    #   Consequently some hacks are employed to map data back to Date or Time
    #   in Ruby. Timezones and sub-second precision on timestamps are
    #   not supported.
    # * Default values that are functions (such as "SYSDATE") are not
    #   supported. This is a restriction of the way ActiveRecord supports
    #   default values.
    #
    # Required parameters:
    #
    # * <tt>:username</tt>
    # * <tt>:password</tt>
    # * <tt>:database</tt> - either TNS alias or connection string for OCI client or database name in JDBC connection string
    # 
    # Optional parameters:
    # 
    # * <tt>:host</tt> - host name for JDBC connection, defaults to "localhost"
    # * <tt>:port</tt> - port number for JDBC connection, defaults to 1521
    # * <tt>:privilege</tt> - set "SYSDBA" if you want to connect with this privilege
    # * <tt>:allow_concurrency</tt> - set to "true" if non-blocking mode should be enabled (just for OCI client)
    # * <tt>:prefetch_rows</tt> - how many rows should be fetched at one time to increase performance, defaults to 100
    # * <tt>:cursor_sharing</tt> - cursor sharing mode to minimize amount of unique statements, defaults to "force"
    # * <tt>:nls_length_semantics</tt> - semantics of size of VARCHAR2 and CHAR columns, defaults to "CHAR"
    #   (meaning that size specifies number of characters and not bytes)
    # * <tt>:time_zone</tt> - database session time zone
    #   (it is recommended to set it using ENV['TZ'] which will be then also used for database session time zone)
    class OracleEnhancedAdapter < AbstractAdapter

      ##
      # :singleton-method:
      # By default, the OracleEnhancedAdapter will consider all columns of type <tt>NUMBER(1)</tt>
      # as boolean. If you wish to disable this emulation you can add the following line
      # to your initializer file:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = false
      cattr_accessor :emulate_booleans
      self.emulate_booleans = true

      ##
      # :singleton-method:
      # By default, the OracleEnhancedAdapter will typecast all columns of type <tt>DATE</tt>
      # to Time or DateTime (if value is out of Time value range) value.
      # If you wish that DATE values with hour, minutes and seconds equal to 0 are typecasted
      # to Date then you can add the following line to your initializer file:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates = true
      # 
      # As this option can have side effects when unnecessary typecasting is done it is recommended
      # that Date columns are explicily defined with +set_date_columns+ method.
      cattr_accessor :emulate_dates
      self.emulate_dates = false

      ##
      # :singleton-method:
      # By default, the OracleEnhancedAdapter will typecast all columns of type <tt>DATE</tt>
      # to Time or DateTime (if value is out of Time value range) value.
      # If you wish that DATE columns with "date" in their name (e.g. "creation_date") are typecasted
      # to Date then you can add the following line to your initializer file:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      # 
      # As this option can have side effects when unnecessary typecasting is done it is recommended
      # that Date columns are explicily defined with +set_date_columns+ method.
      cattr_accessor :emulate_dates_by_column_name
      self.emulate_dates_by_column_name = false

      # Check column name to identify if it is Date (and not Time) column.
      # Is used if +emulate_dates_by_column_name+ option is set to +true+.
      # Override this method definition in initializer file if different Date column recognition is needed.
      def self.is_date_column?(name, table_name = nil)
        name =~ /(^|_)date(_|$)/i
      end

      # instance method uses at first check if column type defined at class level
      def is_date_column?(name, table_name = nil) #:nodoc:
        case get_type_for_column(table_name, name)
        when nil
          self.class.is_date_column?(name, table_name)
        when :date
          true
        else
          false
        end
      end

      ##
      # :singleton-method:
      # By default, the OracleEnhancedAdapter will typecast all columns of type <tt>NUMBER</tt>
      # (without precision or scale) to Float or BigDecimal value.
      # If you wish that NUMBER columns with name "id" or that end with "_id" are typecasted
      # to Integer then you can add the following line to your initializer file:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      cattr_accessor :emulate_integers_by_column_name
      self.emulate_integers_by_column_name = false

      # Check column name to identify if it is Integer (and not Float or BigDecimal) column.
      # Is used if +emulate_integers_by_column_name+ option is set to +true+.
      # Override this method definition in initializer file if different Integer column recognition is needed.
      def self.is_integer_column?(name, table_name = nil)
        name =~ /(^|_)id$/i
      end

      ##
      # :singleton-method:
      # If you wish that CHAR(1), VARCHAR2(1) columns or VARCHAR2 columns with FLAG or YN at the end of their name
      # are typecasted to booleans then you can add the following line to your initializer file:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      cattr_accessor :emulate_booleans_from_strings
      self.emulate_booleans_from_strings = false

      # Check column name to identify if it is boolean (and not String) column.
      # Is used if +emulate_booleans_from_strings+ option is set to +true+.
      # Override this method definition in initializer file if different boolean column recognition is needed.
      def self.is_boolean_column?(name, field_type, table_name = nil)
        return true if ["CHAR(1)","VARCHAR2(1)"].include?(field_type)
        field_type =~ /^VARCHAR2/ && (name =~ /_flag$/i || name =~ /_yn$/i)
      end
      
      # How boolean value should be quoted to String.
      # Used if +emulate_booleans_from_strings+ option is set to +true+.
      def self.boolean_to_string(bool)
        bool ? "Y" : "N"
      end

      ##
      # :singleton-method:
      # Specify non-default date format that should be used when assigning string values to :date columns, e.g.:
      # 
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = “%d.%m.%Y”
      cattr_accessor :string_to_date_format
      self.string_to_date_format = nil
      
      ##
      # :singleton-method:
      # Specify non-default time format that should be used when assigning string values to :datetime columns, e.g.:
      # 
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = “%d.%m.%Y %H:%M:%S”
      cattr_accessor :string_to_time_format
      self.string_to_time_format = nil

      def initialize(connection, logger = nil) #:nodoc:
        super
        @quoted_column_names, @quoted_table_names = {}, {}
      end

      ADAPTER_NAME = 'OracleEnhanced'.freeze
      
      def adapter_name #:nodoc:
        ADAPTER_NAME
      end

      def supports_migrations? #:nodoc:
        true
      end

      def supports_savepoints? #:nodoc:
        true
      end

      #:stopdoc:
      NATIVE_DATABASE_TYPES = {
        :primary_key => "NUMBER(38) NOT NULL PRIMARY KEY",
        :string      => { :name => "VARCHAR2", :limit => 255 },
        :text        => { :name => "CLOB" },
        :integer     => { :name => "NUMBER", :limit => 38 },
        :float       => { :name => "NUMBER" },
        :decimal     => { :name => "DECIMAL" },
        :datetime    => { :name => "DATE" },
        # changed to native TIMESTAMP type
        # :timestamp   => { :name => "DATE" },
        :timestamp   => { :name => "TIMESTAMP" },
        :time        => { :name => "DATE" },
        :date        => { :name => "DATE" },
        :binary      => { :name => "BLOB" },
        :boolean     => { :name => "NUMBER", :limit => 1 }
      }
      # if emulate_booleans_from_strings then store booleans in VARCHAR2
      NATIVE_DATABASE_TYPES_BOOLEAN_STRINGS = NATIVE_DATABASE_TYPES.dup.merge(
        :boolean     => { :name => "VARCHAR2", :limit => 1 }
      )
      #:startdoc:

      def native_database_types #:nodoc:
        emulate_booleans_from_strings ? NATIVE_DATABASE_TYPES_BOOLEAN_STRINGS : NATIVE_DATABASE_TYPES
      end

      # maximum length of Oracle identifiers
      IDENTIFIER_MAX_LENGTH = 30

      def table_alias_length #:nodoc:
        IDENTIFIER_MAX_LENGTH
      end

      # QUOTING ==================================================
      #
      # see: abstract/quoting.rb

      def quote_column_name(name) #:nodoc:
        # camelCase column names need to be quoted; not that anyone using Oracle
        # would really do this, but handling this case means we pass the test...
        @quoted_column_names[name] = name.to_s =~ /[A-Z]/ ? "\"#{name}\"" : quote_oracle_reserved_words(name)
      end

      # unescaped table name should start with letter and
      # contain letters, digits, _, $ or #
      # can be prefixed with schema name
      # CamelCase table names should be quoted
      def self.valid_table_name?(name) #:nodoc:
        name = name.to_s
        name =~ /\A([A-Za-z_0-9]+\.)?[a-z][a-z_0-9\$#]*(@[A-Za-z_0-9\.]+)?\Z/ ||
        name =~ /\A([A-Za-z_0-9]+\.)?[A-Z][A-Z_0-9\$#]*(@[A-Za-z_0-9\.]+)?\Z/ ? true : false
      end

      def quote_table_name(name) #:nodoc:
        # abstract_adapter calls quote_column_name from quote_table_name, so prevent that
        @quoted_table_names[name] ||= if self.class.valid_table_name?(name)
          name
        else
          "\"#{name}\""
        end
      end
      
      def quote_string(s) #:nodoc:
        s.gsub(/'/, "''")
      end

      def quote(value, column = nil) #:nodoc:
        if value && column
          case column.type
          when :text, :binary
            %Q{empty_#{ column.sql_type.downcase rescue 'blob' }()}
          # NLS_DATE_FORMAT independent TIMESTAMP support
          when :timestamp
            quote_timestamp_with_to_timestamp(value)
          # NLS_DATE_FORMAT independent DATE support
          when :date, :time, :datetime
            quote_date_with_to_date(value)
          else
            super
          end
        elsif value.acts_like?(:date)
          quote_date_with_to_date(value)
        elsif value.acts_like?(:time)
          value.to_i == value.to_f ? quote_date_with_to_date(value) : quote_timestamp_with_to_timestamp(value)
        else
          super
        end
      end

      def quoted_true #:nodoc:
        return "'#{self.class.boolean_to_string(true)}'" if emulate_booleans_from_strings
        "1"
      end

      def quoted_false #:nodoc:
        return "'#{self.class.boolean_to_string(false)}'" if emulate_booleans_from_strings
        "0"
      end

      def quote_date_with_to_date(value) #:nodoc:
        # should support that composite_primary_keys gem will pass date as string
        value = quoted_date(value) if value.acts_like?(:date) || value.acts_like?(:time)
        "TO_DATE('#{value}','YYYY-MM-DD HH24:MI:SS')"
      end

      def quote_timestamp_with_to_timestamp(value) #:nodoc:
        # add up to 9 digits of fractional seconds to inserted time
        value = "#{quoted_date(value)}:#{("%.6f"%value.to_f).split('.')[1]}" if value.acts_like?(:time)
        "TO_TIMESTAMP('#{value}','YYYY-MM-DD HH24:MI:SS:FF6')"
      end

      # CONNECTION MANAGEMENT ====================================
      #

      # If SQL statement fails due to lost connection then reconnect
      # and retry SQL statement if autocommit mode is enabled.
      # By default this functionality is disabled.
      attr_reader :auto_retry #:nodoc:
      @auto_retry = false

      def auto_retry=(value) #:nodoc:
        @auto_retry = value
        @connection.auto_retry = value if @connection
      end

      # return raw OCI8 or JDBC connection
      def raw_connection
        @connection.raw_connection
      end

      # Returns true if the connection is active.
      def active? #:nodoc:
        # Pings the connection to check if it's still good. Note that an
        # #active? method is also available, but that simply returns the
        # last known state, which isn't good enough if the connection has
        # gone stale since the last use.
        @connection.ping
      rescue OracleEnhancedConnectionException
        false
      end

      # Reconnects to the database.
      def reconnect! #:nodoc:
        @connection.reset!
      rescue OracleEnhancedConnectionException => e
        @logger.warn "#{adapter_name} automatic reconnection failed: #{e.message}" if @logger
      end

      # Disconnects from the database.
      def disconnect! #:nodoc:
        @connection.logoff rescue nil
      end

      # DATABASE STATEMENTS ======================================
      #
      # see: abstract/database_statements.rb

      # Executes a SQL statement
      def execute(sql, name = nil)
        # hack to pass additional "with_returning" option without changing argument list
        log(sql, name) { sql.instance_variable_get(:@with_returning) ? @connection.exec_with_returning(sql) : @connection.exec(sql) }
      end

      # Returns an array of arrays containing the field values.
      # Order is the same as that returned by #columns.
      def select_rows(sql, name = nil)
        # last parameter indicates to return also column list
        result, columns = select(sql, name, true)
        result.map{ |v| columns.map{|c| v[c]} }
      end

      # Executes an INSERT statement and returns the new record's ID
      def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) #:nodoc:
        # if primary key value is already prefetched from sequence
        # or if there is no primary key
        if id_value || pk.nil?
          execute(sql, name)
          return id_value
        end

        sql_with_returning = sql.dup << @connection.returning_clause(quote_column_name(pk))
        # hack to pass additional "with_returning" option without changing argument list
        sql_with_returning.instance_variable_set(:@with_returning, true)
        clear_query_cache
        execute(sql_with_returning, name)
      end
      protected :insert_sql

      # use in set_sequence_name to avoid fetching primary key value from sequence
      AUTOGENERATED_SEQUENCE_NAME = 'autogenerated'.freeze

      # Returns the next sequence value from a sequence generator. Not generally
      # called directly; used by ActiveRecord to get the next primary key value
      # when inserting a new database record (see #prefetch_primary_key?).
      def next_sequence_value(sequence_name)
        # if sequence_name is set to :autogenerated then it means that primary key will be populated by trigger
        return nil if sequence_name == AUTOGENERATED_SEQUENCE_NAME
        select_one("SELECT #{quote_table_name(sequence_name)}.NEXTVAL id FROM dual")['id']
      end

      def begin_db_transaction #:nodoc:
        @connection.autocommit = false
      end

      def commit_db_transaction #:nodoc:
        @connection.commit
      ensure
        @connection.autocommit = true
      end

      def rollback_db_transaction #:nodoc:
        @connection.rollback
      ensure
        @connection.autocommit = true
      end

      def create_savepoint #:nodoc:
        execute("SAVEPOINT #{current_savepoint_name}")
      end

      def rollback_to_savepoint #:nodoc:
        execute("ROLLBACK TO #{current_savepoint_name}")
      end

      def release_savepoint #:nodoc:
        # there is no RELEASE SAVEPOINT statement in Oracle
      end

      def add_limit_offset!(sql, options) #:nodoc:
        # added to_i for limit and offset to protect from SQL injection
        offset = (options[:offset] || 0).to_i

        if limit = options[:limit]
          limit = limit.to_i
          sql.replace "select * from (select raw_sql_.*, rownum raw_rnum_ from (#{sql}) raw_sql_ where rownum <= #{offset+limit}) where raw_rnum_ > #{offset}"
        elsif offset > 0
          sql.replace "select * from (select raw_sql_.*, rownum raw_rnum_ from (#{sql}) raw_sql_) where raw_rnum_ > #{offset}"
        end
      end

      @@do_not_prefetch_primary_key = {}

      # Returns true for Oracle adapter (since Oracle requires primary key
      # values to be pre-fetched before insert). See also #next_sequence_value.
      def prefetch_primary_key?(table_name = nil)
        ! @@do_not_prefetch_primary_key[table_name.to_s]
      end

      # used just in tests to clear prefetch primary key flag for all tables
      def clear_prefetch_primary_key #:nodoc:
        @@do_not_prefetch_primary_key = {}
      end

      # Returns default sequence name for table.
      # Will take all or first 26 characters of table name and append _seq suffix
      def default_sequence_name(table_name, primary_key = nil)
        # TODO: remove schema prefix if present before truncating
        # truncate table name if necessary to fit in max length of identifier
        "#{table_name.to_s[0,IDENTIFIER_MAX_LENGTH-4]}_seq"
      end

      # Inserts the given fixture into the table. Overridden to properly handle lobs.
      def insert_fixture(fixture, table_name) #:nodoc:
        super

        klass = fixture.class_name.constantize rescue nil
        if klass.respond_to?(:ancestors) && klass.ancestors.include?(ActiveRecord::Base)
          write_lobs(table_name, klass, fixture)
        end
      end

      # Writes LOB values from attributes, as indicated by the LOB columns of klass.
      def write_lobs(table_name, klass, attributes) #:nodoc:
        # is class with composite primary key>
        is_with_cpk = klass.respond_to?(:composite?) && klass.composite?
        if is_with_cpk
          id = klass.primary_key.map {|pk| attributes[pk.to_s] }
        else
          id = quote(attributes[klass.primary_key])
        end
        klass.columns.select { |col| col.sql_type =~ /LOB$/i }.each do |col|
          value = attributes[col.name]
          # changed sequence of next two lines - should check if value is nil before converting to yaml
          next if value.nil?  || (value == '')
          value = value.to_yaml if col.text? && klass.serialized_attributes[col.name]
          uncached do
            if is_with_cpk
              lob = select_one("SELECT #{col.name} FROM #{table_name} WHERE #{klass.composite_where_clause(id)} FOR UPDATE",
                                'Writable Large Object')[col.name]
            else
              lob = select_one("SELECT #{col.name} FROM #{table_name} WHERE #{klass.primary_key} = #{id} FOR UPDATE",
                               'Writable Large Object')[col.name]
            end
            @connection.write_lob(lob, value.to_s, col.type == :binary)
          end
        end
      end

      # change LOB column for ORDER BY clause
      # just first 100 characters are taken for ordering
      def lob_order_by_expression(klass, order) #:nodoc:
        return order if order.nil?
        changed = false
        new_order = order.to_s.strip.split(/, */).map do |order_by_col|
          column_name, asc_desc = order_by_col.split(/ +/)
          if column = klass.columns.detect { |col| col.name == column_name && col.sql_type =~ /LOB$/i}
            changed = true
            "DBMS_LOB.SUBSTR(#{column_name},100,1) #{asc_desc}"
          else
            order_by_col
          end
        end.join(', ')
        changed ? new_order : order
      end

      # SCHEMA STATEMENTS ========================================
      #
      # see: abstract/schema_statements.rb

      # Current database name
      def current_database
        select_value("select sys_context('userenv','db_name') from dual")
      end

      # Current database session user
      def current_user
        select_value("select sys_context('userenv','session_user') from dual")
      end

      # Default tablespace name of current user
      def default_tablespace
        select_value("select lower(default_tablespace) from user_users where username = sys_context('userenv','session_user')")
      end

      def tables(name = nil) #:nodoc:
        # changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select decode(table_name,upper(table_name),lower(table_name),table_name) name from all_tables where owner = sys_context('userenv','session_user')").map {|t| t['name']}
      end

      cattr_accessor :all_schema_indexes #:nodoc:

      # This method selects all indexes at once, and caches them in a class variable.
      # Subsequent index calls get them from the variable, without going to the DB.
      def indexes(table_name, name = nil) #:nodoc:
        (owner, table_name, db_link) = @connection.describe(table_name)
        unless all_schema_indexes
          default_tablespace_name = default_tablespace
          result = select_all(<<-SQL)
            SELECT lower(i.table_name) as table_name, lower(i.index_name) as index_name, i.uniqueness, lower(i.tablespace_name) as tablespace_name, lower(c.column_name) as column_name, e.column_expression as column_expression
              FROM all_indexes#{db_link} i
              JOIN all_ind_columns#{db_link} c on c.index_name = i.index_name and c.index_owner = i.owner
              LEFT OUTER JOIN all_ind_expressions#{db_link} e on e.index_name = i.index_name and e.index_owner = i.owner and e.column_position = c.column_position
             WHERE i.owner = '#{owner}'
               AND i.table_owner = '#{owner}'
               AND NOT EXISTS (SELECT uc.index_name FROM all_constraints uc WHERE uc.index_name = i.index_name AND uc.owner = i.owner AND uc.constraint_type = 'P')
              ORDER BY i.index_name, c.column_position
          SQL

          current_index = nil
          self.all_schema_indexes = []

          result.each do |row|
            # have to keep track of indexes because above query returns dups
            # there is probably a better query we could figure out
            if current_index != row['index_name']
              all_schema_indexes << OracleEnhancedIndexDefinition.new(row['table_name'], row['index_name'], row['uniqueness'] == "UNIQUE",
                row['tablespace_name'] == default_tablespace_name ? nil : row['tablespace_name'], [])
              current_index = row['index_name']
            end
            all_schema_indexes.last.columns << (row['column_expression'].nil? ? row['column_name'] : row['column_expression'].gsub('"','').downcase)
          end
        end

        # Return the indexes just for the requested table, since AR is structured that way
        table_name = table_name.downcase
        all_schema_indexes.select{|i| i.table == table_name}
      end

      @@ignore_table_columns = nil #:nodoc:

      # set ignored columns for table
      def ignore_table_columns(table_name, *args) #:nodoc:
        @@ignore_table_columns ||= {}
        @@ignore_table_columns[table_name] ||= []
        @@ignore_table_columns[table_name] += args.map{|a| a.to_s.downcase}
        @@ignore_table_columns[table_name].uniq!
      end
      
      def ignored_table_columns(table_name) #:nodoc:
        @@ignore_table_columns ||= {}
        @@ignore_table_columns[table_name]
      end
      
      # used just in tests to clear ignored table columns
      def clear_ignored_table_columns #:nodoc:
        @@ignore_table_columns = nil
      end

      @@table_column_type = nil #:nodoc:

      # set explicit type for specified table columns
      def set_type_for_columns(table_name, column_type, *args) #:nodoc:
        @@table_column_type ||= {}
        @@table_column_type[table_name] ||= {}
        args.each do |col|
          @@table_column_type[table_name][col.to_s.downcase] = column_type
        end
      end
      
      def get_type_for_column(table_name, column_name) #:nodoc:
        @@table_column_type && @@table_column_type[table_name] && @@table_column_type[table_name][column_name.to_s.downcase]
      end

      # used just in tests to clear column data type definitions
      def clear_types_for_columns #:nodoc:
        @@table_column_type = nil
      end

      # check if table has primary key trigger with _pkt suffix
      def has_primary_key_trigger?(table_name, owner = nil, desc_table_name = nil, db_link = nil)
        (owner, desc_table_name, db_link) = @connection.describe(table_name) unless owner

        trigger_name = default_trigger_name(table_name).upcase
        pkt_sql = <<-SQL
          SELECT trigger_name
          FROM all_triggers#{db_link}
          WHERE owner = '#{owner}'
            AND trigger_name = '#{trigger_name}'
            AND table_owner = '#{owner}'
            AND table_name = '#{desc_table_name}'
            AND status = 'ENABLED'
        SQL
        select_value(pkt_sql) ? true : false
      end

      ##
      # :singleton-method:
      # Cache column description between requests.
      # Could be used in development environment to avoid selecting table columns from data dictionary tables for each request.
      # This can speed up request processing in development mode if development database is not on local computer.
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
      cattr_accessor :cache_columns
      self.cache_columns = false

      def columns(table_name, name = nil) #:nodoc:
        # Don't double cache if config.cache_classes is turned on
        if @@cache_columns && !(defined?(Rails) && Rails.configuration.cache_classes)
          @@columns_cache ||= {}
          @@columns_cache[table_name] ||= columns_without_cache(table_name, name)
        else
          columns_without_cache(table_name, name)
        end
      end

      def columns_without_cache(table_name, name = nil) #:nodoc:
        # get ignored_columns by original table name
        ignored_columns = ignored_table_columns(table_name)

        (owner, desc_table_name, db_link) = @connection.describe(table_name)

        if has_primary_key_trigger?(table_name, owner, desc_table_name, db_link)
          @@do_not_prefetch_primary_key[table_name] = true
        end

        table_cols = <<-SQL
          select column_name as name, data_type as sql_type, data_default, nullable,
                 decode(data_type, 'NUMBER', data_precision,
                                   'FLOAT', data_precision,
                                   'VARCHAR2', decode(char_used, 'C', char_length, data_length),
                                   'CHAR', decode(char_used, 'C', char_length, data_length),
                                    null) as limit,
                 decode(data_type, 'NUMBER', data_scale, null) as scale
            from all_tab_columns#{db_link}
           where owner      = '#{owner}'
             and table_name = '#{desc_table_name}'
           order by column_id
        SQL

        # added deletion of ignored columns
        select_all(table_cols, name).delete_if do |row|
          ignored_columns && ignored_columns.include?(row['name'].downcase)
        end.map do |row|
          limit, scale = row['limit'], row['scale']
          if limit || scale
            row['sql_type'] << "(#{(limit || 38).to_i}" + ((scale = scale.to_i) > 0 ? ",#{scale})" : ")")
          end

          # clean up odd default spacing from Oracle
          if row['data_default']
            row['data_default'].sub!(/^(.*?)\s*$/, '\1')
            row['data_default'].sub!(/^'(.*)'$/, '\1')
            row['data_default'] = nil if row['data_default'] =~ /^(null|empty_[bc]lob\(\))$/i
          end

          OracleEnhancedColumn.new(oracle_downcase(row['name']),
                           row['data_default'],
                           row['sql_type'],
                           row['nullable'] == 'Y',
                           # pass table name for table specific column definitions
                           table_name,
                           # pass column type if specified in class definition
                           get_type_for_column(table_name, oracle_downcase(row['name'])))
        end
      end

      # used just in tests to clear column cache
      def clear_columns_cache #:nodoc:
        @@columns_cache = nil
      end

      # used in migrations to clear column cache for specified table
      def clear_table_columns_cache(table_name)
        @@columns_cache[table_name.to_s] = nil if @@cache_columns
      end

      ##
      # :singleton-method:
      # Specify default sequence start with value (by default 10000 if not explicitly set), e.g.:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 1
      cattr_accessor :default_sequence_start_value
      self.default_sequence_start_value = 10000

      # Additional options for +create_table+ method in migration files.
      #
      # You can specify individual starting value in table creation migration file, e.g.:
      #
      #   create_table :users, :sequence_start_value => 100 do |t|
      #     # ...
      #   end
      #
      # You can also specify other sequence definition additional parameters, e.g.:
      #
      #   create_table :users, :sequence_start_value => “100 NOCACHE INCREMENT BY 10” do |t|
      #     # ...
      #   end
      #
      # Create primary key trigger (so that you can skip primary key value in INSERT statement).
      # By default trigger name will be "table_name_pkt", you can override the name with 
      # :trigger_name option (but it is not recommended to override it as then this trigger will
      # not be detected by ActiveRecord model and it will still do prefetching of sequence value).
      # Example:
      # 
      #   create_table :users, :primary_key_trigger => true do |t|
      #     # ...
      #   end
      #
      # It is possible to add table and column comments in table creation migration files:
      #
      #   create_table :employees, :comment => “Employees and contractors” do |t|
      #     t.string      :first_name, :comment => “Given name”
      #     t.string      :last_name, :comment => “Surname”
      #   end
      
      def create_table(name, options = {}, &block)
        create_sequence = options[:id] != false
        column_comments = {}
        
        table_definition = TableDefinition.new(self)
        table_definition.primary_key(options[:primary_key] || Base.get_primary_key(name.to_s.singularize)) unless options[:id] == false

        # store that primary key was defined in create_table block
        unless create_sequence
          class << table_definition
            attr_accessor :create_sequence
            def primary_key(*args)
              self.create_sequence = true
              super(*args)
            end
          end
        end

        # store column comments
        class << table_definition
          attr_accessor :column_comments
          def column(name, type, options = {})
            if options[:comment]
              self.column_comments ||= {}
              self.column_comments[name] = options[:comment]
            end
            super(name, type, options)
          end
        end

        result = block.call(table_definition) if block
        create_sequence = create_sequence || table_definition.create_sequence
        column_comments = table_definition.column_comments if table_definition.column_comments


        if options[:force] && table_exists?(name)
          drop_table(name, options)
        end

        create_sql = "CREATE#{' GLOBAL TEMPORARY' if options[:temporary]} TABLE "
        create_sql << "#{quote_table_name(name)} ("
        create_sql << table_definition.to_sql
        create_sql << ") #{options[:options]}"
        execute create_sql
        
        create_sequence_and_trigger(name, options) if create_sequence
        
        add_table_comment name, options[:comment]
        column_comments.each do |column_name, comment|
          add_comment name, column_name, comment
        end
        
      end

      def rename_table(name, new_name) #:nodoc:
        execute "RENAME #{quote_table_name(name)} TO #{quote_table_name(new_name)}"
        execute "RENAME #{quote_table_name("#{name}_seq")} TO #{quote_table_name("#{new_name}_seq")}" rescue nil
      end

      def drop_table(name, options = {}) #:nodoc:
        super(name)
        seq_name = options[:sequence_name] || default_sequence_name(name)
        execute "DROP SEQUENCE #{quote_table_name(seq_name)}" rescue nil
      ensure
        clear_table_columns_cache(name)
      end

      # clear cached indexes when adding new index
      def add_index(table_name, column_name, options = {}) #:nodoc:
        self.all_schema_indexes = nil
        column_names = Array(column_name)
        index_name   = index_name(table_name, :column => column_names)

        if Hash === options # legacy support, since this param was a string
          index_type = options[:unique] ? "UNIQUE" : ""
          index_name = options[:name] || index_name
          tablespace = if options[:tablespace]
                         " TABLESPACE #{options[:tablespace]}"
                       else
                         ""
                       end
        else
          index_type = options
        end
        quoted_column_names = column_names.map { |e| quote_column_name(e) }.join(", ")
        execute "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{quoted_column_names})#{tablespace}"
      end

      # clear cached indexes when removing index
      def remove_index(table_name, options = {}) #:nodoc:
        self.all_schema_indexes = nil
        execute "DROP INDEX #{index_name(table_name, options)}"
      end
      
      # returned shortened index name if default is too large
      def index_name(table_name, options) #:nodoc:
        default_name = super(table_name, options)
        return default_name if default_name.length <= IDENTIFIER_MAX_LENGTH
        
        # remove 'index', 'on' and 'and' keywords
        shortened_name = "i_#{table_name}_#{Array(options[:column]) * '_'}"
        
        # leave just first three letters from each word
        if shortened_name.length > IDENTIFIER_MAX_LENGTH
          shortened_name = shortened_name.split('_').map{|w| w[0,3]}.join('_')
        end
        # generate unique name using hash function
        if shortened_name.length > OracleEnhancedAdapter::IDENTIFIER_MAX_LENGTH
          shortened_name = 'i'+Digest::SHA1.hexdigest(default_name)[0,OracleEnhancedAdapter::IDENTIFIER_MAX_LENGTH-1]
        end
        @logger.warn "#{adapter_name} shortened default index name #{default_name} to #{shortened_name}" if @logger
        shortened_name
      end

      def add_column(table_name, column_name, type, options = {}) #:nodoc:
        add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        options[:type] = type
        add_column_options!(add_column_sql, options)
        execute(add_column_sql)
      ensure
        clear_table_columns_cache(table_name)
      end

      def change_column_default(table_name, column_name, default) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} DEFAULT #{quote(default)}"
      ensure
        clear_table_columns_cache(table_name)
      end

      def change_column_null(table_name, column_name, null, default = nil) #:nodoc:
        column = column_for(table_name, column_name)

        unless null || default.nil?
          execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
        end

        change_column table_name, column_name, column.sql_type, :null => null
      end

      def change_column(table_name, column_name, type, options = {}) #:nodoc:
        column = column_for(table_name, column_name)

        # remove :null option if its value is the same as current column definition
        # otherwise Oracle will raise error
        if options.has_key?(:null) && options[:null] == column.null
          options[:null] = nil
        end

        change_column_sql = "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        options[:type] = type
        add_column_options!(change_column_sql, options)
        execute(change_column_sql)
      ensure
        clear_table_columns_cache(table_name)
      end

      def rename_column(table_name, column_name, new_column_name) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}"
      ensure
        clear_table_columns_cache(table_name)
      end

      def remove_column(table_name, column_name) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)}"
      ensure
        clear_table_columns_cache(table_name)
      end

      def add_comment(table_name, column_name, comment) #:nodoc:
        return if comment.blank?
        execute "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{column_name} IS '#{comment}'"
      end

      def add_table_comment(table_name, comment) #:nodoc:
        return if comment.blank?
        execute "COMMENT ON TABLE #{quote_table_name(table_name)} IS '#{comment}'"
      end

      def table_comment(table_name) #:nodoc:
        (owner, table_name, db_link) = @connection.describe(table_name)
        select_value <<-SQL
          SELECT comments FROM all_tab_comments#{db_link}
          WHERE owner = '#{owner}'
            AND table_name = '#{table_name}'
        SQL
      end

      def column_comment(table_name, column_name) #:nodoc:
        (owner, table_name, db_link) = @connection.describe(table_name)
        select_value <<-SQL
          SELECT comments FROM all_col_comments#{db_link}
          WHERE owner = '#{owner}'
            AND table_name = '#{table_name}'
            AND column_name = '#{column_name.upcase}'
        SQL
      end

      # Maps logical Rails types to Oracle-specific data types.
      def type_to_sql(type, limit = nil, precision = nil, scale = nil) #:nodoc:
        # Ignore options for :text and :binary columns
        return super(type, nil, nil, nil) if ['text', 'binary'].include?(type.to_s)

        super
      end

      # Find a table's primary key and sequence. 
      # *Note*: Only primary key is implemented - sequence will be nil.
      def pk_and_sequence_for(table_name) #:nodoc:
        (owner, table_name, db_link) = @connection.describe(table_name)

        # changed select from all_constraints to user_constraints - much faster in large data dictionaries
        pks = select_values(<<-SQL, 'Primary Key')
          select cc.column_name
            from user_constraints#{db_link} c, user_cons_columns#{db_link} cc
           where c.owner = '#{owner}'
             and c.table_name = '#{table_name}'
             and c.constraint_type = 'P'
             and cc.owner = c.owner
             and cc.constraint_name = c.constraint_name
        SQL

        # only support single column keys
        pks.size == 1 ? [oracle_downcase(pks.first), nil] : nil
      end

      def structure_dump #:nodoc:
        s = select_all("select sequence_name from user_sequences order by 1").inject("") do |structure, seq|
          structure << "create sequence #{seq.to_a.first.last}#{STATEMENT_TOKEN}"
        end

        # changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') order by 1").inject(s) do |structure, table|
          table_name = table['table_name']
          virtual_columns = virtual_columns_for(table_name)
          ddl = "create#{ ' global temporary' if temporary_table?(table_name)} table #{table_name} (\n "
          cols = select_all(%Q{
            select column_name, data_type, data_length, char_used, char_length, data_precision, data_scale, data_default, nullable
            from user_tab_columns
            where table_name = '#{table_name}'
            order by column_id
          }).map do |row|
            if(v = virtual_columns.find {|col| col['column_name'] == row['column_name']})
              structure_dump_virtual_column(row, v['data_default'])
            else
              structure_dump_column(row)
            end
          end
          ddl << cols.join(",\n ")
          ddl << structure_dump_constraints(table_name)
          ddl << "\n)#{STATEMENT_TOKEN}"
          structure << ddl
          structure << structure_dump_indexes(table_name)
        end
      end
      
      def structure_dump_virtual_column(column, data_default) #:nodoc:
        data_default = data_default.gsub(/"/, '')
        col = "#{column['column_name'].downcase} #{column['data_type'].downcase}"
        if column['data_type'] =='NUMBER' and !column['data_precision'].nil?
          col << "(#{column['data_precision'].to_i}"
          col << ",#{column['data_scale'].to_i}" if !column['data_scale'].nil?
          col << ')'
        elsif column['data_type'].include?('CHAR')
          length = column['char_used'] == 'C' ? column['char_length'].to_i : column['data_length'].to_i
          col <<  "(#{length})"
        end
        col << " GENERATED ALWAYS AS (#{data_default}) VIRTUAL"
      end
      
      def structure_dump_column(column) #:nodoc:
        col = "#{column['column_name'].downcase} #{column['data_type'].downcase}"
        if column['data_type'] =='NUMBER' and !column['data_precision'].nil?
          col << "(#{column['data_precision'].to_i}"
          col << ",#{column['data_scale'].to_i}" if !column['data_scale'].nil?
          col << ')'
        elsif column['data_type'].include?('CHAR')
          length = column['char_used'] == 'C' ? column['char_length'].to_i : column['data_length'].to_i
          col <<  "(#{length})"
        end
        col << " default #{column['data_default']}" if !column['data_default'].nil?
        col << ' not null' if column['nullable'] == 'N'
        col  
      end
      
      def structure_dump_constraints(table) #:nodoc:
        out = [structure_dump_primary_key(table), structure_dump_unique_keys(table)].flatten.compact
        out.length > 0 ? ",\n#{out.join(",\n")}" : ''
      end
      
      def structure_dump_primary_key(table) #:nodoc:
        opts = {:name => '', :cols => []}
        pks = select_all(<<-SQL, "Primary Keys") 
          select a.constraint_name, a.column_name, a.position
            from user_cons_columns a 
            join user_constraints c  
              on a.constraint_name = c.constraint_name 
           where c.table_name = '#{table.upcase}' 
             and c.constraint_type = 'P'
             and c.owner = sys_context('userenv', 'session_user')
        SQL
        pks.each do |row|
          opts[:name] = row['constraint_name']
          opts[:cols][row['position']-1] = row['column_name']
        end
        opts[:cols].length > 0 ? " CONSTRAINT #{opts[:name]} PRIMARY KEY (#{opts[:cols].join(',')})" : nil
      end
      
      def structure_dump_unique_keys(table) #:nodoc:
        keys = {}
        uks = select_all(<<-SQL, "Primary Keys") 
          select a.constraint_name, a.column_name, a.position
            from user_cons_columns a 
            join user_constraints c  
              on a.constraint_name = c.constraint_name 
           where c.table_name = '#{table.upcase}' 
             and c.constraint_type = 'U'
             and c.owner = sys_context('userenv', 'session_user')
        SQL
        uks.each do |uk|
          keys[uk['constraint_name']] ||= []
          keys[uk['constraint_name']][uk['position']-1] = uk['column_name']
        end
        keys.map do |k,v|
          " CONSTRAINT #{k} UNIQUE (#{v.join(',')})"
        end
      end
      
      def structure_dump_fk_constraints #:nodoc:
        fks = select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') order by 1").map do |table|
          if respond_to?(:foreign_keys) && (foreign_keys = foreign_keys(table["table_name"])).any?
            foreign_keys.map do |fk|
              column = fk.options[:column] || "#{fk.to_table.to_s.singularize}_id"
              constraint_name = foreign_key_constraint_name(fk.from_table, column, fk.options)
              sql = "ALTER TABLE #{quote_table_name(fk.from_table)} ADD CONSTRAINT #{quote_column_name(constraint_name)} "
              sql << "#{foreign_key_definition(fk.to_table, fk.options)}"
            end
          end
        end.flatten.compact.join(STATEMENT_TOKEN)
        fks.length > 1 ? "#{fks}#{STATEMENT_TOKEN}" : ''
      end
      
      # Extract all stored procedures, packages, synonyms and views.
      def structure_dump_db_stored_code #:nodoc:
        structure = ""
        select_all("select distinct name, type 
                     from all_source 
                    where type in ('PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'TRIGGER', 'TYPE') 
                      and  owner = sys_context('userenv','session_user') order by type").each do |source|
          ddl = "create or replace   \n "
          lines = select_all(%Q{
                  select text
                    from all_source
                   where name = '#{source['name']}'
                     and type = '#{source['type']}'
                     and owner = sys_context('userenv','session_user')
                   order by line 
                }).map do |row|
            ddl << row['text'] if row['text'].size > 1
          end
          ddl << ";" unless ddl.strip.last == ";"
          structure << ddl << STATEMENT_TOKEN
        end

        # export views 
        select_all("select view_name, text from user_views").each do |view|
          ddl = "create or replace view #{view['view_name']} AS\n "
          # any views with empty lines will cause OCI to barf when loading. remove blank lines =/ 
          ddl << view['text'].gsub(/^\n/, '') 
          structure << ddl << STATEMENT_TOKEN
        end

        # export synonyms 
        select_all("select owner, synonym_name, table_name, table_owner 
                      from all_synonyms  
                     where owner = sys_context('userenv','session_user') ").each do |synonym|
          ddl = "create or replace #{synonym['owner'] == 'PUBLIC' ? 'PUBLIC' : '' } SYNONYM #{synonym['synonym_name']} for #{synonym['table_owner']}.#{synonym['table_name']}"
          structure << ddl << STATEMENT_TOKEN
        end

        structure
      end

      def structure_dump_indexes(table_name) #:nodoc:
        statements = indexes(table_name).map do |options|
        #def add_index(table_name, column_name, options = {})
          column_names = options[:columns]
          options = {:name => options[:name], :unique => options[:unique]}
          index_name   = index_name(table_name, :column => column_names)
          if Hash === options # legacy support, since this param was a string
            index_type = options[:unique] ? "UNIQUE" : ""
            index_name = options[:name] || index_name
          else
            index_type = options
          end
          quoted_column_names = column_names.map { |e| quote_column_name(e) }.join(", ")
          "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{quoted_column_names})"
        end
        statements.length > 0 ? "#{statements.join(STATEMENT_TOKEN)}#{STATEMENT_TOKEN}" : ''
      end
      
      def structure_drop #:nodoc:
        s = select_all("select sequence_name from user_sequences order by 1").inject("") do |drop, seq|
          drop << "drop sequence #{seq.to_a.first.last};\n\n"
        end

        # changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') order by 1").inject(s) do |drop, table|
          drop << "drop table #{table.to_a.first.last} cascade constraints;\n\n"
        end
      end
      
      def temp_table_drop #:nodoc:
        # changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') and temporary = 'Y' order by 1").inject('') do |drop, table|
          drop << "drop table #{table.to_a.first.last} cascade constraints;\n\n"
        end
      end
      
      def full_drop(preserve_tables=false) #:nodoc:
        s = preserve_tables ? [] : [structure_drop]
        s << temp_table_drop if preserve_tables
        s << drop_sql_for_feature("view")
        s << drop_sql_for_feature("synonym")
        s << drop_sql_for_feature("type")
        s << drop_sql_for_object("package")
        s << drop_sql_for_object("function")
        s << drop_sql_for_object("procedure")
        s.join("\n\n")
      end
      
      def add_column_options!(sql, options) #:nodoc:
        type = options[:type] || ((column = options[:column]) && column.type)
        type = type && type.to_sym
        # handle case of defaults for CLOB columns, which would otherwise get "quoted" incorrectly
        if options_include_default?(options)
          if type == :text
            sql << " DEFAULT #{quote(options[:default])}"
          else
            # from abstract adapter
            sql << " DEFAULT #{quote(options[:default], options[:column])}"
          end
        end
        # must explicitly add NULL or NOT NULL to allow change_column to work on migrations
        if options[:null] == false
          sql << " NOT NULL"
        elsif options[:null] == true
          sql << " NULL" unless type == :primary_key
        end
      end

      # SELECT DISTINCT clause for a given set of columns and a given ORDER BY clause.
      #
      # Oracle requires the ORDER BY columns to be in the SELECT list for DISTINCT
      # queries. However, with those columns included in the SELECT DISTINCT list, you
      # won't actually get a distinct list of the column you want (presuming the column
      # has duplicates with multiple values for the ordered-by columns. So we use the 
      # FIRST_VALUE function to get a single (first) value for each column, effectively
      # making every row the same.
      #
      #   distinct("posts.id", "posts.created_at desc")
      def distinct(columns, order_by) #:nodoc:
        return "DISTINCT #{columns}" if order_by.blank?

        # construct a valid DISTINCT clause, ie. one that includes the ORDER BY columns, using
        # FIRST_VALUE such that the inclusion of these columns doesn't invalidate the DISTINCT
        order_columns = order_by.split(',').map { |s| s.strip }.reject(&:blank?)
        order_columns = order_columns.zip((0...order_columns.size).to_a).map do |c, i|
          "FIRST_VALUE(#{c.split.first}) OVER (PARTITION BY #{columns} ORDER BY #{c}) AS alias_#{i}__"
        end
        sql = "DISTINCT #{columns}, "
        sql << order_columns * ", "
      end

      def temporary_table?(table_name) #:nodoc:
        select_value("select temporary from user_tables where table_name = '#{table_name.upcase}'") == 'Y'
      end
      
      # statements separator used in structure dump
      STATEMENT_TOKEN = "\n\n--@@@--\n\n"
      
      # ORDER BY clause for the passed order option.
      # 
      # Uses column aliases as defined by #distinct.
      def add_order_by_for_association_limiting!(sql, options) #:nodoc:
        return sql if options[:order].blank?

        order = options[:order].split(',').collect { |s| s.strip }.reject(&:blank?)
        order.map! {|s| $1 if s =~ / (.*)/}
        order = order.zip((0...order.size).to_a).map { |s,i| "alias_#{i}__ #{s}" }.join(', ')

        sql << " ORDER BY #{order}"
      end

      protected

      def translate_exception(exception, message) #:nodoc:
        case @connection.error_code(exception)
        when 1
          RecordNotUnique.new(message, exception)
        when 2291
          InvalidForeignKey.new(message, exception)
        else
          super
        end
      end

      private

      def select(sql, name = nil, return_column_names = false)
        log(sql, name) do
          @connection.select(sql, name, return_column_names)
        end
      end

      def oracle_downcase(column_name)
        @connection.oracle_downcase(column_name)
      end

      def column_for(table_name, column_name)
        unless column = columns(table_name).find { |c| c.name == column_name.to_s }
          raise "No such column: #{table_name}.#{column_name}"
        end
        column
      end

      def create_sequence_and_trigger(table_name, options)
        seq_name = options[:sequence_name] || default_sequence_name(table_name)
        seq_start_value = options[:sequence_start_value] || default_sequence_start_value
        execute "CREATE SEQUENCE #{quote_table_name(seq_name)} START WITH #{seq_start_value}"

        create_primary_key_trigger(table_name, options) if options[:primary_key_trigger]
      end
      
      def create_primary_key_trigger(table_name, options)
        seq_name = options[:sequence_name] || default_sequence_name(table_name)
        trigger_name = options[:trigger_name] || default_trigger_name(table_name)
        primary_key = options[:primary_key] || Base.get_primary_key(table_name.to_s.singularize)
        execute compress_lines(<<-SQL)
          CREATE OR REPLACE TRIGGER #{quote_table_name(trigger_name)}
          BEFORE INSERT ON #{quote_table_name(table_name)} FOR EACH ROW
          BEGIN
            IF inserting THEN
              IF :new.#{quote_column_name(primary_key)} IS NULL THEN
                SELECT #{quote_table_name(seq_name)}.NEXTVAL INTO :new.#{quote_column_name(primary_key)} FROM dual;
              END IF;
            END IF;
          END;
        SQL
      end

      def default_trigger_name(table_name)
        # truncate table name if necessary to fit in max length of identifier
        "#{table_name.to_s[0,IDENTIFIER_MAX_LENGTH-4]}_pkt"
      end

      def compress_lines(string, spaced = true)
        string.split($/).map { |line| line.strip }.join(spaced ? ' ' : '')
      end

      # virtual columns are an 11g feature.  This returns [] if feature is not 
      # present or none are found.
      # return [{'column_name' => 'FOOS', 'data_default' => '...'}, ...]
      def virtual_columns_for(table)
        begin
          select_all <<-SQL
            select column_name, data_default 
              from user_tab_cols 
             where virtual_column='YES' 
               and table_name='#{table.upcase}'
          SQL
        # feature not supported previous to 11g
        rescue ActiveRecord::StatementInvalid => e
          []
        end
      end
      
      def drop_sql_for_feature(type)
        select_values("select 'DROP #{type.upcase} \"' || #{type}_name || '\";' from user_#{type.tableize}").join("\n\n")
      end
      
      def drop_sql_for_object(type)
        select_values("select 'DROP #{type.upcase} ' || object_name || ';' from user_objects where object_type = '#{type.upcase}'").join("\n\n")
      end
      
      public
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

      protected
      def log(sql, name) #:nodoc:
        super sql, name
      ensure
        log_dbms_output if dbms_output_enabled?
      end
      
      private

      def set_dbms_output_plsql_connection
        raise OracleEnhancedConnectionException, "ruby-plsql gem is required for logging DBMS output" unless self.respond_to?(:plsql)
        # do not reset plsql connection if it is the same (as resetting will clear PL/SQL metadata cache)
        unless plsql(:dbms_output).connection && plsql(:dbms_output).connection.raw_connection == raw_connection
          plsql(:dbms_output).connection = raw_connection
        end
      end

      def log_dbms_output
        while true do
          result = plsql(:dbms_output).sys.dbms_output.get_line(:line => '', :status => 0)
          break unless result[:status] == 0
          @logger.debug "DBMS_OUTPUT: #{result[:line]}"
        end
      end

    end
  end
end

# Added LOB writing callback for sessions stored in database
# Otherwise it is not working as Session class is defined before OracleAdapter is loaded in Rails 2.0
if defined?(CGI::Session::ActiveRecordStore::Session)
  if !CGI::Session::ActiveRecordStore::Session.respond_to?(:after_save_callback_chain) ||
      CGI::Session::ActiveRecordStore::Session.after_save_callback_chain.detect{|cb| cb.method == :enhanced_write_lobs}.nil?
    #:stopdoc:
    class CGI::Session::ActiveRecordStore::Session
      after_save :enhanced_write_lobs
    end
    #:startdoc:
  end
end

# Load custom create, update, delete methods functionality
require 'active_record/connection_adapters/oracle_enhanced_procedures'

# Load additional methods for composite_primary_keys support
require 'active_record/connection_adapters/oracle_enhanced_cpk'

# Load patch for dirty tracking methods
require 'active_record/connection_adapters/oracle_enhanced_dirty'

# Load rake tasks definitions
begin
  require 'active_record/connection_adapters/oracle_enhanced_tasks'
rescue LoadError
end if defined?(RAILS_ROOT)

# Handles quoting of oracle reserved words
require 'active_record/connection_adapters/oracle_enhanced_reserved_words'

# Patches and enhancements for schema dumper
require 'active_record/connection_adapters/oracle_enhanced_schema_dumper'

# Extensions for schema definition statements
require 'active_record/connection_adapters/oracle_enhanced_schema_statements_ext'

# Extensions for schema definition
require 'active_record/connection_adapters/oracle_enhanced_schema_definitions'

# Add BigDecimal#to_d, Fixnum#to_d and Bignum#to_d methods if not already present
require 'active_record/connection_adapters/oracle_enhanced_core_ext'

require 'active_record/connection_adapters/oracle_enhanced_version'
