# oracle_enhanced_adapter.rb -- ActiveRecord adapter for Oracle 8i, 9i, 10g, 11g
#
# Authors or original oracle_adapter: Graham Jenkins, Michael Schoen
#
# Current maintainer: Raimonds Simanovskis (http://blog.rayapps.com)
#
#########################################################################
#
# See History.md for changes added to original oracle_adapter.rb
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
require 'active_record/connection_adapters/oracle_enhanced/connection'
require 'active_record/connection_adapters/oracle_enhanced/database_statements'
require 'active_record/connection_adapters/oracle_enhanced/schema_statements'
require 'active_record/connection_adapters/oracle_enhanced/schema_statements_ext'
require 'active_record/connection_adapters/oracle_enhanced/column_dumper'
require 'active_record/connection_adapters/oracle_enhanced/context_index'
require 'active_record/connection_adapters/oracle_enhanced/column'
require 'active_record/connection_adapters/oracle_enhanced/quoting'

require 'digest/sha1'

ActiveRecord::Base.class_eval do
  class_attribute :custom_create_method, :custom_update_method, :custom_delete_method
end

module ActiveRecord
  class Base

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
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        'set_date_columns` has been deprecated. Please use Rails attribute API.
      MSG
      # connection.set_type_for_columns(table_name,:date,*args)
    end

    # Specify which table columns should be typecasted to Time (or DateTime), e.g.:
    #
    #   set_datetime_columns :created_date, :updated_date
    def self.set_datetime_columns(*args)
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        'set_datetime_columns` has been deprecated. Please use Rails attribute API.
      MSG
      # connection.set_type_for_columns(table_name,:datetime,*args)
    end

    # Specify which table columns should be typecasted to boolean values +true+ or +false+, e.g.:
    #
    #   set_boolean_columns :is_valid, :is_completed
    def self.set_boolean_columns(*args)
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        'set_boolean_columns` has been deprecated. Please use Rails attribute API.
      MSG
      # connection.set_type_for_columns(table_name,:boolean,*args)
    end

    # Specify which table columns should be typecasted to integer values.
    # Might be useful to force NUMBER(1) column to be integer and not boolean, or force NUMBER column without
    # scale to be retrieved as integer and not decimal. Example:
    #
    #   set_integer_columns :version_number, :object_identifier
    def self.set_integer_columns(*args)
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        'set_integer_columns` has been deprecated. Please use Rails attribute API.
      MSG
      # connection.set_type_for_columns(table_name,:integer,*args)
    end

    # Specify which table columns should be typecasted to string values.
    # Might be useful to specify that columns should be string even if its name matches boolean column criteria.
    #
    #   set_string_columns :active_flag
    def self.set_string_columns(*args)
      ActiveSupport::Deprecation.warn(<<-MSG.squish)
        'set_string_columns` has been deprecated. Please use Rails attribute API.
      MSG
      # connection.set_type_for_columns(table_name,:string,*args)
    end

    # Get table comment from schema definition.
    def self.table_comment
      #TODO: may be deprecated
      connection.table_comment(self.table_name)
    end

    def self.lob_columns
      columns.select do |column|
        column.respond_to?(:lob?) && column.lob?
      end
    end

    def self.virtual_columns
      columns.select do |column|
        column.respond_to?(:virtual?) && column.virtual?
      end
    end

    def arel_attributes_with_values(attribute_names)
      virtual_column_names = self.class.virtual_columns.map(&:name)
      super(attribute_names - virtual_column_names)
    end

    # After setting large objects to empty, select the OCI8::LOB
    # and write back the data.
    before_update :record_changed_lobs
    after_update :enhanced_write_lobs

    private

    def enhanced_write_lobs
      if self.class.connection.is_a?(ConnectionAdapters::OracleEnhancedAdapter) &&
          !(
            (self.class.custom_create_method || self.class.custom_create_method) ||
            (self.class.custom_update_method || self.class.custom_update_method)
          )
        self.class.connection.write_lobs(self.class.table_name, self.class, attributes, @changed_lob_columns)
      end
    end

    def record_changed_lobs
      @changed_lob_columns = self.class.lob_columns.select do |col|
        self.attribute_changed?(col.name) && !self.class.readonly_attributes.to_a.include?(col.name)
      end
    end
  end
end

module ActiveRecord
  module ConnectionHandling #:nodoc:
    # Establishes a connection to the database that's used by all Active Record objects.
    def oracle_enhanced_connection(config) #:nodoc:
      if config[:emulate_oracle_adapter] == true
        # allows the enhanced adapter to look like the OracleAdapter. Useful to pick up
        # conditionals in the rails activerecord test suite
        require 'active_record/connection_adapters/emulation/oracle_adapter'
        ConnectionAdapters::OracleAdapter.new(
          ConnectionAdapters::OracleEnhancedConnection.create(config), logger, config)
      else
        ConnectionAdapters::OracleEnhancedAdapter.new(
          ConnectionAdapters::OracleEnhancedConnection.create(config), logger, config)
      end
    end
  end

  module ConnectionAdapters #:nodoc:

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
    # * <tt>:time_zone</tt> - database session time zone
    #   (it is recommended to set it using ENV['TZ'] which will be then also used for database session time zone)
    #
    # Optionals NLS parameters:
    #
    # * <tt>:nls_calendar</tt>
    # * <tt>:nls_comp</tt>
    # * <tt>:nls_currency</tt>
    # * <tt>:nls_date_format</tt> - format for :date columns, defaults to <tt>YYYY-MM-DD HH24:MI:SS</tt>
    # * <tt>:nls_date_language</tt>
    # * <tt>:nls_dual_currency</tt>
    # * <tt>:nls_iso_currency</tt>
    # * <tt>:nls_language</tt>
    # * <tt>:nls_length_semantics</tt> - semantics of size of VARCHAR2 and CHAR columns, defaults to <tt>CHAR</tt>
    #   (meaning that size specifies number of characters and not bytes)
    # * <tt>:nls_nchar_conv_excp</tt>
    # * <tt>:nls_numeric_characters</tt>
    # * <tt>:nls_sort</tt>
    # * <tt>:nls_territory</tt>
    # * <tt>:nls_timestamp_format</tt> - format for :timestamp columns, defaults to <tt>YYYY-MM-DD HH24:MI:SS:FF6</tt>
    # * <tt>:nls_timestamp_tz_format</tt>
    # * <tt>:nls_time_format</tt>
    # * <tt>:nls_time_tz_format</tt>
    #
    class OracleEnhancedAdapter < AbstractAdapter
      # TODO: Use relative
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::DatabaseStatements
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::SchemaStatements
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::SchemaStatementsExt
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::ColumnDumper
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::ContextIndex
      include ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting

      def schema_creation
        OracleEnhanced::SchemaCreation.new self
      end

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
        # OracleEnhancedAdapter will use the default tablespace, but if you want specific types of
        # objects to go into specific tablespaces, specify them like this in an initializer:
        #
        #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces =
        #  {:clob => 'TS_LOB', :blob => 'TS_LOB', :index => 'TS_INDEX', :table => 'TS_DATA'}
        #
        # Using the :tablespace option where available (e.g create_table) will take precedence
        # over these settings.
      cattr_accessor :default_tablespaces
      self.default_tablespaces={}

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
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `self.is_date_column?` has been deprecated. Please use Rails attribute API.
        MSG
        return false
        # name =~ /(^|_)date(_|$)/i
      end

      # instance method uses at first check if column type defined at class level
      def is_date_column?(name, table_name = nil) #:nodoc:
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `is_date_column?` has been deprecated. Please use Rails attribute API.
        MSG
        return false
        #case get_type_for_column(table_name, name)
        #when nil
        #  self.class.is_date_column?(name, table_name)
        #when :date
        #  true
        #else
        #  false
        #end
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
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `is_integer_column?` has been deprecated. Please use Rails attribute API.
        MSG
        return false
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
      def self.is_boolean_column?(name, sql_type, table_name = nil)
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `is_boolean_column?` has been deprecated. Please use Rails attribute API.
        MSG
        return false
        # return true if ["CHAR(1)","VARCHAR2(1)"].include?(sql_type)
        # sql_type =~ /^VARCHAR2/ && (name =~ /_flag$/i || name =~ /_yn$/i)
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

      class StatementPool
        include Enumerable

        def initialize(connection, max = 300)
          @connection = connection
          @max        = max
          @cache      = {}
        end

        def each(&block); @cache.each(&block); end
        def key?(key);    @cache.key?(key); end
        def [](key);      @cache[key]; end
        def length;       @cache.length; end
        def delete(key);  @cache.delete(key); end

        def []=(sql, key)
          while @max <= @cache.size
            @cache.shift.last.close
          end
          @cache[sql] = key
        end

        def clear
          @cache.values.each do |cursor|
            cursor.close
          end
          @cache.clear
        end
      end

      def initialize(connection, logger = nil, config = {}) # :nodoc:
        super(connection, logger, config)
        @quoted_column_names, @quoted_table_names = {}, {}
        @statements = StatementPool.new(connection, config.fetch(:statement_limit) { 250 })
        @enable_dbms_output = false
      end

      ADAPTER_NAME = 'OracleEnhanced'.freeze

      def adapter_name #:nodoc:
        ADAPTER_NAME
      end

      def arel_visitor # :nodoc:
        if supports_fetch_first_n_rows_and_offset?
          Arel::Visitors::Oracle12.new(self)
        else
          Arel::Visitors::Oracle.new(self)
        end
      end

      def supports_migrations? #:nodoc:
        true
      end

      def supports_primary_key? #:nodoc:
        true
      end

      def supports_savepoints? #:nodoc:
        true
      end

      def supports_transaction_isolation? #:nodoc:
        true
      end

      def supports_foreign_keys?
        true
      end

      def supports_views?
        true
      end

      def supports_fetch_first_n_rows_and_offset?
        if @connection.database_version == [12,1]
          true
        else
          false
        end
      end

      def supports_datetime_with_precision?
        #TODO: Needs to consider to return false to keep old behaviour
        #to map :datetime as DATE
        @connection.database_version.first >= 9
      end

      def supports_comments?
        true
      end

      #:stopdoc:
      DEFAULT_NLS_PARAMETERS = {
        :nls_calendar            => nil,
        :nls_comp                => nil,
        :nls_currency            => nil,
        :nls_date_format         => 'YYYY-MM-DD HH24:MI:SS',
        :nls_date_language       => nil,
        :nls_dual_currency       => nil,
        :nls_iso_currency        => nil,
        :nls_language            => nil,
        :nls_length_semantics    => 'CHAR',
        :nls_nchar_conv_excp     => nil,
        :nls_numeric_characters  => nil,
        :nls_sort                => nil,
        :nls_territory           => nil,
        :nls_timestamp_format    => 'YYYY-MM-DD HH24:MI:SS:FF6',
        :nls_timestamp_tz_format => nil,
        :nls_time_format         => nil,
        :nls_time_tz_format      => nil
      }

      #:stopdoc:
      NATIVE_DATABASE_TYPES = {
        :primary_key => "NUMBER(38) NOT NULL PRIMARY KEY",
        :string      => { :name => "VARCHAR2", :limit => 255 },
        :text        => { :name => "CLOB" },
        :integer     => { :name => "NUMBER", :limit => 38 },
        :float       => { :name => "BINARY_FLOAT" },
        :decimal     => { :name => "DECIMAL" },
        :datetime    => { :name => "TIMESTAMP" },
        :timestamp   => { :name => "TIMESTAMP" },
        :time        => { :name => "TIMESTAMP" },
        :date        => { :name => "DATE" },
        :binary      => { :name => "BLOB" },
        :boolean     => { :name => "NUMBER", :limit => 1 },
        :raw         => { :name => "RAW", :limit => 2000 },
        :bigint      => { :name => "NUMBER", :limit => 19 }
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

      # the maximum length of a table name
      def table_name_length
        IDENTIFIER_MAX_LENGTH
      end

      # the maximum length of a column name
      def column_name_length
        IDENTIFIER_MAX_LENGTH
      end

      # Returns the maximum allowed length for an index name. This
      # limit is enforced by rails and Is less than or equal to
      # <tt>index_name_length</tt>. The gap between
      # <tt>index_name_length</tt> is to allow internal rails
      # opreations to use prefixes in temporary opreations.
      def allowed_index_name_length
        index_name_length
      end

      # the maximum length of an index name
      # supported by this database
      def index_name_length
        IDENTIFIER_MAX_LENGTH
      end

      # the maximum length of a sequence name
      def sequence_name_length
        IDENTIFIER_MAX_LENGTH
      end

      # To avoid ORA-01795: maximum number of expressions in a list is 1000
      # tell ActiveRecord to limit us to 1000 ids at a time
      def in_clause_length
        1000
      end
      alias ids_in_list_limit in_clause_length

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
        super
        @connection.reset!
      rescue OracleEnhancedConnectionException => e
        @logger.warn "#{adapter_name} automatic reconnection failed: #{e.message}" if @logger
      end

      def reset!
        clear_cache!
        super
      end

      # Disconnects from the database.
      def disconnect! #:nodoc:
        super
        @connection.logoff rescue nil
      end

      # use in set_sequence_name to avoid fetching primary key value from sequence
      AUTOGENERATED_SEQUENCE_NAME = 'autogenerated'.freeze

      # Returns the next sequence value from a sequence generator. Not generally
      # called directly; used by ActiveRecord to get the next primary key value
      # when inserting a new database record (see #prefetch_primary_key?).
      def next_sequence_value(sequence_name)
        # if sequence_name is set to :autogenerated then it means that primary key will be populated by trigger
        return nil if sequence_name == AUTOGENERATED_SEQUENCE_NAME
        # call directly connection method to avoid prepared statement which causes fetching of next sequence value twice
        @connection.select_value("SELECT #{quote_table_name(sequence_name)}.NEXTVAL FROM dual")
      end

      @@do_not_prefetch_primary_key = {}

      # Returns true for Oracle adapter (since Oracle requires primary key
      # values to be pre-fetched before insert). See also #next_sequence_value.
      def prefetch_primary_key?(table_name = nil)
        return true if table_name.nil?
        table_name = table_name.to_s
        do_not_prefetch = @@do_not_prefetch_primary_key[table_name]
        if do_not_prefetch.nil?
          owner, desc_table_name, db_link = @connection.describe(table_name)
          @@do_not_prefetch_primary_key[table_name] = do_not_prefetch =
            !has_primary_key?(table_name, owner, desc_table_name, db_link) ||
            has_primary_key_trigger?(table_name, owner, desc_table_name, db_link)
        end
        !do_not_prefetch
      end

      # used just in tests to clear prefetch primary key flag for all tables
      def clear_prefetch_primary_key #:nodoc:
        @@do_not_prefetch_primary_key = {}
      end

      def reset_pk_sequence!(table_name, primary_key = nil, sequence_name = nil) #:nodoc:
        return nil unless data_source_exists?(table_name)
        unless primary_key and sequence_name
        # *Note*: Only primary key is implemented - sequence will be nil.
          primary_key, sequence_name = pk_and_sequence_for(table_name)
          # TODO This sequence_name implemantation is just enough
          # to satisty fixures. To get correct sequence_name always
          # pk_and_sequence_for method needs some work.
          begin
            sequence_name = table_name.classify.constantize.sequence_name
          rescue
            sequence_name = default_sequence_name(table_name)
          end
        end

        if @logger && primary_key && !sequence_name
          @logger.warn "#{table_name} has primary key #{primary_key} with no default sequence"
        end

        if primary_key && sequence_name
          new_start_value = select_value("
            select NVL(max(#{quote_column_name(primary_key)}),0) + 1 from #{quote_table_name(table_name)}
          ", new_start_value)

          execute "DROP SEQUENCE #{quote_table_name(sequence_name)}"
          execute "CREATE SEQUENCE #{quote_table_name(sequence_name)} START WITH #{new_start_value}"
        end
      end

      # Writes LOB values from attributes for specified columns
      def write_lobs(table_name, klass, attributes, columns) #:nodoc:
        # is class with composite primary key>
        is_with_cpk = klass.respond_to?(:composite?) && klass.composite?
        if is_with_cpk
          id = klass.primary_key.map {|pk| attributes[pk.to_s] }
        else
          id = quote(attributes[klass.primary_key])
        end
        columns.each do |col|
          value = attributes[col.name]
          # changed sequence of next two lines - should check if value is nil before converting to yaml
          next if value.blank?
          if klass.attribute_types[col.name].is_a? ActiveRecord::Type::Serialized
            value = klass.attribute_types[col.name].serialize(value)
          end
          uncached do
            sql = is_with_cpk ? "SELECT #{quote_column_name(col.name)} FROM #{quote_table_name(table_name)} WHERE #{klass.composite_where_clause(id)} FOR UPDATE" :
              "SELECT #{quote_column_name(col.name)} FROM #{quote_table_name(table_name)} WHERE #{quote_column_name(klass.primary_key)} = #{id} FOR UPDATE"
            unless lob_record = select_one(sql, 'Writable Large Object')
              raise ActiveRecord::RecordNotFound, "statement #{sql} returned no rows"
            end
            lob = lob_record[col.name]
            @connection.write_lob(lob, value.to_s, col.type == :binary)
          end
        end
      end

      # Current database name
      def current_database
        select_value("SELECT SYS_CONTEXT('userenv', 'db_name') FROM dual")
      end

      # Current database session user
      def current_user
        select_value("SELECT SYS_CONTEXT('userenv', 'session_user') FROM dual")
      end

      # Current database session schema
      def current_schema
        select_value("SELECT SYS_CONTEXT('userenv', 'current_schema') FROM dual")
      end

      # Default tablespace name of current user
      def default_tablespace
        select_value("SELECT LOWER(default_tablespace) FROM user_users WHERE username = SYS_CONTEXT('userenv', 'current_schema')")
      end

      def tables(name = nil) #:nodoc:
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          #tables currently returns both tables and views.
          This behavior is deprecated and will be changed with Rails 5.1 to only return tables.
          Use #data_sources instead.
        MSG

        if name
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            Passing arguments to #tables is deprecated without replacement.
          MSG
        end

        data_sources
      end


      def data_sources
        select_values(
        "SELECT DECODE(table_name, UPPER(table_name), LOWER(table_name), table_name) FROM all_tables WHERE owner = SYS_CONTEXT('userenv', 'current_schema') AND secondary = 'N'",
        'SCHEMA')
      end

      def table_exists?(table_name)
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          #table_exists? currently checks both tables and views.
          This behavior is deprecated and will be changed with Rails 5.1 to only check tables.
          Use #data_source_exists? instead.
        MSG

        data_source_exists?(table_name)
      end

      # Will return true if database object exists (to be able to use also views and synonyms for ActiveRecord models)
      # Needs to consider how to support synonyms in Rails 5.1
      def data_source_exists?(table_name)
        (_owner, table_name, _db_link) = @connection.describe(table_name)
        true
      rescue
        false
      end

      def views # :nodoc:
        select_values("SELECT LOWER(view_name) FROM all_views WHERE owner = SYS_CONTEXT('userenv', 'session_user')")
      end

      def materialized_views #:nodoc:
        select_values("SELECT LOWER(mview_name) FROM all_mviews WHERE owner = SYS_CONTEXT('userenv', 'current_schema')")
      end

      cattr_accessor :all_schema_indexes #:nodoc:

      # This method selects all indexes at once, and caches them in a class variable.
      # Subsequent index calls get them from the variable, without going to the DB.
      def indexes(table_name, name = nil) #:nodoc:
        (owner, table_name, db_link) = @connection.describe(table_name)
        unless all_schema_indexes
          default_tablespace_name = default_tablespace
          result = select_all(<<-SQL.strip.gsub(/\s+/, ' '))
            SELECT LOWER(i.table_name) AS table_name, LOWER(i.index_name) AS index_name, i.uniqueness,
              i.index_type, i.ityp_owner, i.ityp_name, i.parameters,
              LOWER(i.tablespace_name) AS tablespace_name,
              LOWER(c.column_name) AS column_name, e.column_expression,
              atc.virtual_column
            FROM all_indexes#{db_link} i
              JOIN all_ind_columns#{db_link} c ON c.index_name = i.index_name AND c.index_owner = i.owner
              LEFT OUTER JOIN all_ind_expressions#{db_link} e ON e.index_name = i.index_name AND
                e.index_owner = i.owner AND e.column_position = c.column_position
              LEFT OUTER JOIN all_tab_cols#{db_link} atc ON i.table_name = atc.table_name AND
                c.column_name = atc.column_name AND i.owner = atc.owner AND atc.hidden_column = 'NO'
            WHERE i.owner = '#{owner}'
               AND i.table_owner = '#{owner}'
               AND NOT EXISTS (SELECT uc.index_name FROM all_constraints uc
                WHERE uc.index_name = i.index_name AND uc.owner = i.owner AND uc.constraint_type = 'P')
            ORDER BY i.index_name, c.column_position
          SQL

          current_index = nil
          self.all_schema_indexes = []

          result.each do |row|
            # have to keep track of indexes because above query returns dups
            # there is probably a better query we could figure out
            if current_index != row['index_name']
              statement_parameters = nil
              if row['index_type'] == 'DOMAIN' && row['ityp_owner'] == 'CTXSYS' && row['ityp_name'] == 'CONTEXT'
                procedure_name = default_datastore_procedure(row['index_name'])
                source = select_values(<<-SQL).join
                  SELECT text
                  FROM all_source#{db_link}
                  WHERE owner = '#{owner}'
                    AND name = '#{procedure_name.upcase}'
                  ORDER BY line
                SQL
                if source =~ /-- add_context_index_parameters (.+)\n/
                  statement_parameters = $1
                end
              end
              all_schema_indexes << OracleEnhanced::IndexDefinition.new(
                row['table_name'],
                row['index_name'],
                row['uniqueness'] == "UNIQUE",
                [],
                nil,
                nil,
                nil,
                row['index_type'] == 'DOMAIN' ? "#{row['ityp_owner']}.#{row['ityp_name']}" : nil,
                nil,
                row['parameters'],
                statement_parameters,
                row['tablespace_name'] == default_tablespace_name ? nil : row['tablespace_name'])
              current_index = row['index_name']
            end

            # Functional index columns and virtual columns both get stored as column expressions,
            # but re-creating a virtual column index as an expression (instead of using the virtual column's name)
            # results in a ORA-54018 error.  Thus, we only want the column expression value returned
            # when the column is not virtual.
            if row['column_expression'] && row['virtual_column'] != 'YES'
              all_schema_indexes.last.columns << row['column_expression']
            else
              all_schema_indexes.last.columns << row['column_name'].downcase
            end
          end
        end

        # Return the indexes just for the requested table, since AR is structured that way
        table_name = table_name.downcase
        all_schema_indexes.select{|i| i.table == table_name}
      end

      @@ignore_table_columns = nil #:nodoc:

      # set ignored columns for table
      def ignore_table_columns(table_name, *args) #:nodoc:
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `ignore_table_columns` will be deprecated in next version of Oracle enhanced adapter
          since Rails 5 introduces `ignored_columns`. Use `ignored_columns` instead of `ignore_table_columns`.
        MSG
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
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `set_type_for_columns` has been deprecated. Please use Rails attribute API.
        MSG
      end

      def get_type_for_column(table_name, column_name) #:nodoc:
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `get_type_for_columns` has been deprecated. Please use Rails attribute API.
        MSG
      end

      # used just in tests to clear column data type definitions
      def clear_types_for_columns #:nodoc:
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `clear_types_for_columns` has been deprecated. Please use Rails attribute API.
        MSG
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
        select_value(pkt_sql, 'Primary Key Trigger') ? true : false
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
        if @@cache_columns
          @@columns_cache ||= {}
          @@columns_cache[table_name] ||= columns_without_cache(table_name, name)
        else
          columns_without_cache(table_name, name)
        end
      end

      def columns_without_cache(table_name, name = nil) #:nodoc:
        table_name = table_name.to_s
        # get ignored_columns by original table name
        ignored_columns = ignored_table_columns(table_name)

        (owner, desc_table_name, db_link) = @connection.describe(table_name)

        # reset do_not_prefetch_primary_key cache for this table
        @@do_not_prefetch_primary_key[table_name] = nil

        table_cols = <<-SQL.strip.gsub(/\s+/, ' ')
          SELECT cols.column_name AS name, cols.data_type AS sql_type,
                 cols.data_default, cols.nullable, cols.virtual_column, cols.hidden_column,
                 cols.data_type_owner AS sql_type_owner,
                 DECODE(cols.data_type, 'NUMBER', data_precision,
                                   'FLOAT', data_precision,
                                   'VARCHAR2', DECODE(char_used, 'C', char_length, data_length),
                                   'RAW', DECODE(char_used, 'C', char_length, data_length),
                                   'CHAR', DECODE(char_used, 'C', char_length, data_length),
                                    NULL) AS limit,
                 DECODE(data_type, 'NUMBER', data_scale, NULL) AS scale,
                 comments.comments as column_comment
            FROM all_tab_cols#{db_link} cols, all_col_comments#{db_link} comments
           WHERE cols.owner      = '#{owner}'
             AND cols.table_name = '#{desc_table_name}'
             AND cols.hidden_column = 'NO'
             AND cols.owner = comments.owner
             AND cols.table_name = comments.table_name
             AND cols.column_name = comments.column_name
           ORDER BY cols.column_id
        SQL

        # added deletion of ignored columns
        select_all(table_cols, name).to_a.delete_if do |row|
          ignored_columns && ignored_columns.include?(row['name'].downcase)
        end.map do |row|
          limit, scale = row['limit'], row['scale']
          if limit || scale
            row['sql_type'] += "(#{(limit || 38).to_i}" + ((scale = scale.to_i) > 0 ? ",#{scale})" : ")")
          end

          if row['sql_type_owner']
            row['sql_type'] = row['sql_type_owner'] + '.' + row['sql_type']
          end

          is_virtual = row['virtual_column']=='YES'

          # clean up odd default spacing from Oracle
          if row['data_default'] && !is_virtual
            row['data_default'].sub!(/^(.*?)\s*$/, '\1')

            # If a default contains a newline these cleanup regexes need to
            # match newlines.
            row['data_default'].sub!(/^'(.*)'$/m, '\1')
            row['data_default'] = nil if row['data_default'] =~ /^(null|empty_[bc]lob\(\))$/i
            # TODO: Needs better fix to fallback "N" to false
            row['data_default'] = false if (row['data_default'] == "N" && OracleEnhancedAdapter.emulate_booleans_from_strings)
          end

          type_metadata = fetch_type_metadata(row['sql_type'])
          new_column(oracle_downcase(row['name']),
                           row['data_default'],
                           type_metadata,
                           row['nullable'] == 'Y',
                           table_name,
                           is_virtual,
                           false,
                           row['column_comment']
                    )
        end
      end

      def new_column(name, default, sql_type_metadata = nil, null = true, table_name = nil, virtual = false, returning_id = false,comment = nil) # :nodoc:
        OracleEnhancedColumn.new(name, default, sql_type_metadata, null, table_name, virtual, returning_id, comment)
      end

      # used just in tests to clear column cache
      def clear_columns_cache #:nodoc:
        @@columns_cache = nil
        @@pk_and_sequence_for_cache = nil
      end

      # used in migrations to clear column cache for specified table
      def clear_table_columns_cache(table_name)
        if @@cache_columns
          @@columns_cache ||= {}
          @@columns_cache[table_name.to_s] = nil
        end
      end

      ##
      # :singleton-method:
      # Specify default sequence start with value (by default 10000 if not explicitly set), e.g.:
      #
      #   ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 1
      cattr_accessor :default_sequence_start_value
      self.default_sequence_start_value = 10000

      # Find a table's primary key and sequence.
      # *Note*: Only primary key is implemented - sequence will be nil.
      def pk_and_sequence_for(table_name, owner=nil, desc_table_name=nil, db_link=nil) #:nodoc:
        if @@cache_columns
          @@pk_and_sequence_for_cache ||= {}
          if @@pk_and_sequence_for_cache.key?(table_name)
            @@pk_and_sequence_for_cache[table_name]
          else
            @@pk_and_sequence_for_cache[table_name] = pk_and_sequence_for_without_cache(table_name, owner, desc_table_name, db_link)
          end
        else
          pk_and_sequence_for_without_cache(table_name, owner, desc_table_name, db_link)
        end
      end

      def pk_and_sequence_for_without_cache(table_name, owner=nil, desc_table_name=nil, db_link=nil) #:nodoc:
        (owner, desc_table_name, db_link) = @connection.describe(table_name) unless owner

        seqs = select_values(<<-SQL.strip.gsub(/\s+/, ' '), 'Sequence')
          select us.sequence_name
          from all_sequences#{db_link} us
          where us.sequence_owner = '#{owner}'
          and us.sequence_name = '#{desc_table_name}_SEQ'
        SQL

        # changed back from user_constraints to all_constraints for consistency
        pks = select_values(<<-SQL.strip.gsub(/\s+/, ' '), 'Primary Key')
          SELECT cc.column_name
            FROM all_constraints#{db_link} c, all_cons_columns#{db_link} cc
           WHERE c.owner = '#{owner}'
             AND c.table_name = '#{desc_table_name}'
             AND c.constraint_type = 'P'
             AND cc.owner = c.owner
             AND cc.constraint_name = c.constraint_name
        SQL

        warn <<-WARNING.strip_heredoc if pks.count > 1
          WARNING: Active Record does not support composite primary key.

          #{table_name} has composite primary key. Composite primary key is ignored.
        WARNING

        # only support single column keys
        pks.size == 1 ? [oracle_downcase(pks.first),
                         oracle_downcase(seqs.first)] : nil
      end

      # Returns just a table's primary key
      def primary_key(table_name)
        pk_and_sequence = pk_and_sequence_for(table_name)
        pk_and_sequence && pk_and_sequence.first
      end

      def has_primary_key?(table_name, owner=nil, desc_table_name=nil, db_link=nil) #:nodoc:
        !pk_and_sequence_for(table_name, owner, desc_table_name, db_link).nil?
      end

      def primary_keys(table_name) # :nodoc:
        (owner, desc_table_name, db_link) = @connection.describe(table_name) unless owner

        pks = select_values(<<-SQL.strip_heredoc, 'Primary Keys')
          SELECT cc.column_name
            FROM all_constraints#{db_link} c, all_cons_columns#{db_link} cc
           WHERE c.owner = '#{owner}'
             AND c.table_name = '#{desc_table_name}'
             AND c.constraint_type = 'P'
             AND cc.owner = c.owner
             AND cc.constraint_name = c.constraint_name
             order by cc.position
        SQL
        pks.map {|pk| oracle_downcase(pk)}
      end

      def columns_for_distinct(columns, orders) #:nodoc:
        # construct a valid columns name for DISTINCT clause,
        # ie. one that includes the ORDER BY columns, using FIRST_VALUE such that
        # the inclusion of these columns doesn't invalidate the DISTINCT
        #
        # It does not construct DISTINCT clause. Just return column names for distinct.
        order_columns = orders.reject(&:blank?).map{ |s|
          s = s.to_sql unless s.is_a?(String)
          # remove any ASC/DESC modifiers
          s.gsub(/\s+(ASC|DESC)\s*?/i, '')
          }.reject(&:blank?).map.with_index { |column,i|
            "FIRST_VALUE(#{column}) OVER (PARTITION BY #{columns} ORDER BY #{column}) AS alias_#{i}__"
          }
          [super, *order_columns].join(', ')
      end

      def temporary_table?(table_name) #:nodoc:
        select_value("SELECT temporary FROM all_tables WHERE table_name = '#{table_name.upcase}' and owner = SYS_CONTEXT('userenv', 'session_user')") == 'Y'
      end

      # construct additional wrapper subquery if select.offset is used to avoid generation of invalid subquery
      # ... IN ( SELECT * FROM ( SELECT raw_sql_.*, rownum raw_rnum_ FROM ( ... ) raw_sql_ ) WHERE raw_rnum_ > ... )
      def join_to_update(update, select, key) #:nodoc:
        #TODO: Need to validate if we can remove join_to_update from Oracle enhanced adapter after testing
        # older version of Oracle 11gR2
        super
      end

      def valid_type?(type)
        !native_database_types[type].nil?
      end

      def combine_bind_parameters(
        from_clause: [],
        join_clause: [],
        where_clause: [],
        having_clause: [],
        limit: nil,
        offset: nil
      ) # :nodoc:
        result = from_clause + join_clause + where_clause + having_clause
        if offset
          result << offset
        end
        if limit
          result << limit
        end
        result
      end

      protected

      def initialize_type_map(m)
        super
        # oracle
        register_class_with_limit m, %r(raw)i,            ActiveRecord::OracleEnhanced::Type::Raw
        register_class_with_limit m, %r(char)i,           ActiveRecord::OracleEnhanced::Type::String
        register_class_with_limit m, %r(clob)i,           ActiveRecord::OracleEnhanced::Type::Text

        m.register_type  'NCHAR', ActiveRecord::OracleEnhanced::Type::NationalCharacterString.new
        m.alias_type %r(NVARCHAR2)i,    'NCHAR'

        m.register_type(%r(NUMBER)i) do |sql_type|
          scale = extract_scale(sql_type)
          precision = extract_precision(sql_type)
          limit = extract_limit(sql_type)
          if scale == 0
            ActiveRecord::OracleEnhanced::Type::Integer.new(precision: precision, limit: limit)
          else
            Type::Decimal.new(precision: precision, scale: scale)
          end
        end

        if OracleEnhancedAdapter.emulate_booleans
          if OracleEnhancedAdapter.emulate_booleans_from_strings
            m.register_type %r(^VARCHAR2\(1\))i, ActiveRecord::OracleEnhanced::Type::Boolean.new
          else
            m.register_type %r(^NUMBER\(1\))i, Type::Boolean.new
          end
        end
      end

      def extract_limit(sql_type) #:nodoc:
        case sql_type
        when /^bigint/i
          19
        when /\((.*)\)/
          $1.to_i
        end
      end

      def translate_exception(exception, message) #:nodoc:
        case @connection.error_code(exception)
        when 1
          RecordNotUnique.new(message)
        when 2291
          InvalidForeignKey.new(message)
        when 12899
          ValueTooLong.new(message)
        else
          super
        end
      end

      private

      def oracle_downcase(column_name)
        @connection.oracle_downcase(column_name)
      end

      def compress_lines(string, join_with = "\n")
        string.split($/).map { |line| line.strip }.join(join_with)
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
      def log(sql, name = "SQL", binds = [], statement_name = nil) #:nodoc:
        super
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
          @logger.debug "DBMS_OUTPUT: #{result[:line]}" if @logger
        end
      end

    end
  end
end

# Implementation of standard schema definition statements and extensions for schema definition
require 'active_record/connection_adapters/oracle_enhanced/schema_statements'
require 'active_record/connection_adapters/oracle_enhanced/schema_statements_ext'

# Extensions for schema definition
require 'active_record/connection_adapters/oracle_enhanced/schema_definitions'

# Extensions for context index definition
require 'active_record/connection_adapters/oracle_enhanced/context_index'

# Load additional methods for composite_primary_keys support
require 'active_record/connection_adapters/oracle_enhanced/cpk'

# Patches and enhancements for schema dumper
require 'active_record/connection_adapters/oracle_enhanced/schema_dumper'

# Implementation of structure dump
require 'active_record/connection_adapters/oracle_enhanced/structure_dump'

require 'active_record/connection_adapters/oracle_enhanced/version'

module ActiveRecord
  autoload :OracleEnhancedProcedures, 'active_record/connection_adapters/oracle_enhanced/procedures'
end

# Patches and enhancements for column dumper
require 'active_record/connection_adapters/oracle_enhanced/column_dumper'

# Moved SchemaCreation class
require 'active_record/connection_adapters/oracle_enhanced/schema_creation'

# Moved DatabaseStetements
require 'active_record/connection_adapters/oracle_enhanced/database_statements'

# Add Type:Raw
require 'active_record/oracle_enhanced/type/raw'

# Add OracleEnhanced::Type::Integer
require 'active_record/oracle_enhanced/type/integer'

# Add OracleEnhanced::Type::String
require 'active_record/oracle_enhanced/type/string'

# Add OracleEnhanced::Type::NationalCharacterString
require 'active_record/oracle_enhanced/type/national_character_string'

# Add OracleEnhanced::Type::Text
require 'active_record/oracle_enhanced/type/text'

# Add OracleEnhanced::Type::Boolean
require 'active_record/oracle_enhanced/type/boolean'
