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

module ActiveRecord
  class Base
    def self.oracle_enhanced_connection(config)
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

    # RSI: specify table columns which should be ifnored
    def self.ignore_table_columns(*args)
      connection.ignore_table_columns(table_name,*args)
    end

    # RSI: specify which table columns should be treated as date (without time)
    def self.set_date_columns(*args)
      connection.set_type_for_columns(table_name,:date,*args)
    end

    # RSI: specify which table columns should be treated as datetime
    def self.set_datetime_columns(*args)
      connection.set_type_for_columns(table_name,:datetime,*args)
    end

    # RSI: specify which table columns should be treated as booleans
    def self.set_boolean_columns(*args)
      connection.set_type_for_columns(table_name,:boolean,*args)
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
      # RSI: patch ORDER BY to work with LOBs
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
      alias_method :add_order_without_lobs!, :add_order!
      alias_method :add_order!, :add_order_with_lobs!
    end
    
    # RSI: get table comment from schema definition
    def self.table_comment
      connection.table_comment(self.table_name)
    end
  end


  module ConnectionAdapters #:nodoc:
    class OracleEnhancedColumn < Column #:nodoc:

      attr_reader :table_name, :forced_column_type
      
      def initialize(name, default, sql_type = nil, null = true, table_name = nil, forced_column_type = nil)
        @table_name = table_name
        @forced_column_type = forced_column_type
        super(name, default, sql_type, null)
      end

      def type_cast(value)
        return guess_date_or_time(value) if type == :datetime && OracleEnhancedAdapter.emulate_dates
        super
      end

      # convert something to a boolean
      # RSI: added y as boolean value
      def self.value_to_boolean(value)
        if value == true || value == false
          value
        elsif value.is_a?(String) && value.blank?
          nil
        else
          %w(true t 1 y +).include?(value.to_s.downcase)
        end
      end

      # RSI: convert Time or DateTime value to Date for :date columns
      def self.string_to_date(string)
        return string.to_date if string.is_a?(Time) || string.is_a?(DateTime)
        super
      end

      # RSI: convert Date value to Time for :datetime columns
      def self.string_to_time(string)
        return string.to_time if string.is_a?(Date) && !OracleEnhancedAdapter.emulate_dates
        super
      end

      # RSI: get column comment from schema definition
      # will work only if using default ActiveRecord connection
      def comment
        ActiveRecord::Base.connection.column_comment(@table_name, name)
      end
      
      private
      def simplified_type(field_type)
        return :boolean if OracleEnhancedAdapter.emulate_booleans && field_type == 'NUMBER(1)'
        return :boolean if OracleEnhancedAdapter.emulate_booleans_from_strings &&
                          (forced_column_type == :boolean ||
                          OracleEnhancedAdapter.is_boolean_column?(name, field_type, table_name))
        
        case field_type
          when /date/i
            forced_column_type ||
            (:date if OracleEnhancedAdapter.emulate_dates_by_column_name && OracleEnhancedAdapter.is_date_column?(name, table_name)) ||
            :datetime
          when /timestamp/i then :timestamp
          when /time/i then :datetime
          when /decimal|numeric|number/i
            return :integer if extract_scale(field_type) == 0
            # RSI: if column name is ID or ends with _ID
            return :integer if OracleEnhancedAdapter.emulate_integers_by_column_name && OracleEnhancedAdapter.is_integer_column?(name, table_name)
            :decimal
          else super
        end
      end

      def guess_date_or_time(value)
        value.respond_to?(:hour) && (value.hour == 0 and value.min == 0 and value.sec == 0) ?
          Date.new(value.year, value.month, value.day) : value
      end
      
      class <<self
        protected

        def fallback_string_to_date(string)
          if OracleEnhancedAdapter.string_to_date_format || OracleEnhancedAdapter.string_to_time_format
            return (string_to_date_or_time_using_format(string).to_date rescue super)
          end
          super
        end

        def fallback_string_to_time(string)
          if OracleEnhancedAdapter.string_to_time_format || OracleEnhancedAdapter.string_to_date_format
            return (string_to_date_or_time_using_format(string).to_time rescue super)
          end
          super
        end

        def string_to_date_or_time_using_format(string)
          if OracleEnhancedAdapter.string_to_time_format && dt=Date._strptime(string, OracleEnhancedAdapter.string_to_time_format)
            return Time.mktime(*dt.values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday))
          end
          DateTime.strptime(string, OracleEnhancedAdapter.string_to_date_format)
        end
        
      end
    end


    # This is an Oracle/OCI adapter for the ActiveRecord persistence
    # framework. It relies upon the OCI8 driver, which works with Oracle 8i
    # and above. Most recent development has been on Debian Linux against
    # a 10g database, ActiveRecord 1.12.1 and OCI8 0.1.13.
    # See: http://rubyforge.org/projects/ruby-oci8/
    #
    # Usage notes:
    # * Key generation assumes a "${table_name}_seq" sequence is available
    #   for all tables; the sequence name can be changed using
    #   ActiveRecord::Base.set_sequence_name. When using Migrations, these
    #   sequences are created automatically.
    # * Oracle uses DATE or TIMESTAMP datatypes for both dates and times.
    #   Consequently some hacks are employed to map data back to Date or Time
    #   in Ruby. If the column_name ends in _time it's created as a Ruby Time.
    #   Else if the hours/minutes/seconds are 0, I make it a Ruby Date. Else
    #   it's a Ruby Time. This is a bit nasty - but if you use Duck Typing
    #   you'll probably not care very much. In 9i and up it's tempting to
    #   map DATE to Date and TIMESTAMP to Time, but too many databases use
    #   DATE for both. Timezones and sub-second precision on timestamps are
    #   not supported.
    # * Default values that are functions (such as "SYSDATE") are not
    #   supported. This is a restriction of the way ActiveRecord supports
    #   default values.
    # * Support for Oracle8 is limited by Rails' use of ANSI join syntax, which
    #   is supported in Oracle9i and later. You will need to use #finder_sql for
    #   has_and_belongs_to_many associations to run against Oracle8.
    #
    # Required parameters:
    #
    # * <tt>:username</tt>
    # * <tt>:password</tt>
    # * <tt>:database</tt>
    class OracleEnhancedAdapter < AbstractAdapter

      @@emulate_booleans = true
      cattr_accessor :emulate_booleans

      @@emulate_dates = false
      cattr_accessor :emulate_dates

      # RSI: set to true if columns with DATE in their name should be emulated as date
      @@emulate_dates_by_column_name = false
      cattr_accessor :emulate_dates_by_column_name
      def self.is_date_column?(name, table_name = nil)
        name =~ /(^|_)date(_|$)/i
      end
      # RSI: instance method uses at first check if column type defined at class level
      def is_date_column?(name, table_name = nil)
        case get_type_for_column(table_name, name)
        when nil
          self.class.is_date_column?(name, table_name)
        when :date
          true
        else
          false
        end
      end

      # RSI: set to true if NUMBER columns with ID at the end of their name should be emulated as integers
      @@emulate_integers_by_column_name = false
      cattr_accessor :emulate_integers_by_column_name
      def self.is_integer_column?(name, table_name = nil)
        name =~ /(^|_)id$/i
      end

      # RSI: set to true if CHAR(1), VARCHAR2(1) columns or VARCHAR2 columns with FLAG or YN at the end of their name
      # should be emulated as booleans
      @@emulate_booleans_from_strings = false
      cattr_accessor :emulate_booleans_from_strings
      def self.is_boolean_column?(name, field_type, table_name = nil)
        return true if ["CHAR(1)","VARCHAR2(1)"].include?(field_type)
        field_type =~ /^VARCHAR2/ && (name =~ /_flag$/i || name =~ /_yn$/i)
      end
      def self.boolean_to_string(bool)
        bool ? "Y" : "N"
      end

      # RSI: use to set NLS specific date formats which will be used when assigning string to :date and :datetime columns
      @@string_to_date_format = @@string_to_time_format = nil
      cattr_accessor :string_to_date_format, :string_to_time_format

      def adapter_name #:nodoc:
        'OracleEnhanced'
      end

      def supports_migrations? #:nodoc:
        true
      end

      def native_database_types #:nodoc:
        {
          :primary_key => "NUMBER(38) NOT NULL PRIMARY KEY",
          :string      => { :name => "VARCHAR2", :limit => 255 },
          :text        => { :name => "CLOB" },
          :integer     => { :name => "NUMBER", :limit => 38 },
          :float       => { :name => "NUMBER" },
          :decimal     => { :name => "DECIMAL" },
          :datetime    => { :name => "DATE" },
          # RSI: changed to native TIMESTAMP type
          # :timestamp   => { :name => "DATE" },
          :timestamp   => { :name => "TIMESTAMP" },
          :time        => { :name => "DATE" },
          :date        => { :name => "DATE" },
          :binary      => { :name => "BLOB" },
          # RSI: if emulate_booleans_from_strings then store booleans in VARCHAR2
          :boolean     => emulate_booleans_from_strings ?
            { :name => "VARCHAR2", :limit => 1 } : { :name => "NUMBER", :limit => 1 }
        }
      end

      def table_alias_length
        30
      end

      # Returns an array of arrays containing the field values.
      # Order is the same as that returned by #columns.
      def select_rows(sql, name = nil)
        # last parameter indicates to return also column list
        result, columns = select(sql, name, true)
        result.map{ |v| columns.map{|c| v[c]} }
      end

      # QUOTING ==================================================
      #
      # see: abstract/quoting.rb

      # camelCase column names need to be quoted; not that anyone using Oracle
      # would really do this, but handling this case means we pass the test...
      def quote_column_name(name) #:nodoc:
        name.to_s =~ /[A-Z]/ ? "\"#{name}\"" : quote_oracle_reserved_words(name)
      end

      # unescaped table name should start with letter and
      # contain letters, digits, _, $ or #
      # can be prefixed with schema name
      # CamelCase table names should be quoted
      def self.valid_table_name?(name)
        name = name.to_s
        name =~ /^([A-Za-z_0-9]+\.)?[a-z][a-z_0-9\$#]*$/ ||
        name =~ /^([A-Za-z_0-9]+\.)?[A-Z][A-Z_0-9\$#]*$/ ? true : false
      end

      # abstract_adapter calls quote_column_name from quote_table_name, so prevent that
      def quote_table_name(name)
        if self.class.valid_table_name?(name)
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
          # RSI: TIMESTAMP support
          when :timestamp
            quote_timestamp_with_to_timestamp(value)
          # RSI: NLS_DATE_FORMAT independent DATE support
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

      def quoted_true
        return "'#{self.class.boolean_to_string(true)}'" if emulate_booleans_from_strings
        "1"
      end

      def quoted_false
        return "'#{self.class.boolean_to_string(false)}'" if emulate_booleans_from_strings
        "0"
      end

      # RSI: should support that composite_primary_keys gem will pass date as string
      def quote_date_with_to_date(value)
        value = value.to_s(:db) if value.acts_like?(:date) || value.acts_like?(:time)
        "TO_DATE('#{value}','YYYY-MM-DD HH24:MI:SS')"
      end

      def quote_timestamp_with_to_timestamp(value)
        # add up to 9 digits of fractional seconds to inserted time
        value = "#{value.to_s(:db)}.#{("%.6f"%value.to_f).split('.')[1]}" if value.acts_like?(:time)
        "TO_TIMESTAMP('#{value}','YYYY-MM-DD HH24:MI:SS.FF6')"
      end

      # CONNECTION MANAGEMENT ====================================
      #

      # If SQL statement fails due to lost connection then reconnect
      # and retry SQL statement if autocommit mode is enabled.
      # By default this functionality is disabled.
      @auto_retry = false
      attr_reader :auto_retry
      def auto_retry=(value)
        @auto_retry = value
        @connection.auto_retry = value if @connection
      end

      def raw_connection
        @connection.raw_connection
      end

      # Returns true if the connection is active.
      def active?
        # Pings the connection to check if it's still good. Note that an
        # #active? method is also available, but that simply returns the
        # last known state, which isn't good enough if the connection has
        # gone stale since the last use.
        @connection.ping
      rescue OracleEnhancedConnectionException
        false
      end

      # Reconnects to the database.
      def reconnect!
        @connection.reset!
      rescue OracleEnhancedConnectionException => e
        @logger.warn "#{adapter_name} automatic reconnection failed: #{e.message}"
      end

      # Disconnects from the database.
      def disconnect!
        @connection.logoff rescue nil
      end


      # DATABASE STATEMENTS ======================================
      #
      # see: abstract/database_statements.rb

      def execute(sql, name = nil) #:nodoc:
        log(sql, name) { @connection.exec sql }
      end

      # Returns the next sequence value from a sequence generator. Not generally
      # called directly; used by ActiveRecord to get the next primary key value
      # when inserting a new database record (see #prefetch_primary_key?).
      def next_sequence_value(sequence_name)
        select_one("select #{sequence_name}.nextval id from dual")['id']
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

      def add_limit_offset!(sql, options) #:nodoc:
        # RSI: added to_i for limit and offset to protect from SQL injection
        offset = (options[:offset] || 0).to_i

        if limit = options[:limit]
          limit = limit.to_i
          sql.replace "select * from (select raw_sql_.*, rownum raw_rnum_ from (#{sql}) raw_sql_ where rownum <= #{offset+limit}) where raw_rnum_ > #{offset}"
        elsif offset > 0
          sql.replace "select * from (select raw_sql_.*, rownum raw_rnum_ from (#{sql}) raw_sql_) where raw_rnum_ > #{offset}"
        end
      end

      # Returns true for Oracle adapter (since Oracle requires primary key
      # values to be pre-fetched before insert). See also #next_sequence_value.
      def prefetch_primary_key?(table_name = nil)
        true
      end

      def default_sequence_name(table, column) #:nodoc:
        quote_table_name("#{table}_seq")
      end


      # Inserts the given fixture into the table. Overridden to properly handle lobs.
      def insert_fixture(fixture, table_name)
        super

        klass = fixture.class_name.constantize rescue nil
        if klass.respond_to?(:ancestors) && klass.ancestors.include?(ActiveRecord::Base)
          write_lobs(table_name, klass, fixture)
        end
      end

      # Writes LOB values from attributes, as indicated by the LOB columns of klass.
      def write_lobs(table_name, klass, attributes)
        # is class with composite primary key>
        is_with_cpk = klass.respond_to?(:composite?) && klass.composite?
        if is_with_cpk
          id = klass.primary_key.map {|pk| attributes[pk.to_s] }
        else
          id = quote(attributes[klass.primary_key])
        end
        klass.columns.select { |col| col.sql_type =~ /LOB$/i }.each do |col|
          value = attributes[col.name]
          # RSI: changed sequence of next two lines - should check if value is nil before converting to yaml
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
            @connection.write_lob(lob, value, col.type == :binary)
          end
        end
      end

      # RSI: change LOB column for ORDER BY clause
      # just first 100 characters are taken for ordering
      def lob_order_by_expression(klass, order)
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

      def current_database #:nodoc:
        select_one("select sys_context('userenv','db_name') db from dual")["db"]
      end

      # RSI: changed select from user_tables to all_tables - much faster in large data dictionaries
      def tables(name = nil) #:nodoc:
        select_all("select decode(table_name,upper(table_name),lower(table_name),table_name) name from all_tables where owner = sys_context('userenv','session_user')").map {|t| t['name']}
      end

      cattr_accessor :all_schema_indexes

      # This method selects all indexes at once, and caches them in a class variable.
      # Subsequent index calls get them from the variable, without going to the DB.
      def indexes(table_name, name = nil)
        (owner, table_name) = @connection.describe(table_name)
        unless all_schema_indexes
          result = select_all(<<-SQL)
            SELECT lower(i.table_name) as table_name, lower(i.index_name) as index_name, i.uniqueness, lower(c.column_name) as column_name
              FROM all_indexes i, all_ind_columns c
             WHERE i.owner = '#{owner}'
               AND i.table_owner = '#{owner}'
               AND c.index_name = i.index_name
               AND c.index_owner = i.owner
               AND NOT EXISTS (SELECT uc.index_name FROM all_constraints uc WHERE uc.index_name = i.index_name AND uc.owner = i.owner AND uc.constraint_type = 'P')
              ORDER BY i.index_name, c.column_position
          SQL
      
          current_index = nil
          self.all_schema_indexes = []
      
          result.each do |row|
            # have to keep track of indexes because above query returns dups
            # there is probably a better query we could figure out
            if current_index != row['index_name']
              self.all_schema_indexes << ::ActiveRecord::ConnectionAdapters::IndexDefinition.new(row['table_name'], row['index_name'], row['uniqueness'] == "UNIQUE", [])
              current_index = row['index_name']
            end
      
            self.all_schema_indexes.last.columns << row['column_name']
          end
        end
      
        # Return the indexes just for the requested table, since AR is structured that way
        table_name = table_name.downcase
        all_schema_indexes.select{|i| i.table == table_name}
      end
      
      # RSI: set ignored columns for table
      def ignore_table_columns(table_name, *args)
        @ignore_table_columns ||= {}
        @ignore_table_columns[table_name] ||= []
        @ignore_table_columns[table_name] += args.map{|a| a.to_s.downcase}
        @ignore_table_columns[table_name].uniq!
      end
      
      def ignored_table_columns(table_name)
        @ignore_table_columns ||= {}
        @ignore_table_columns[table_name]
      end
      
      # RSI: set explicit type for specified table columns
      def set_type_for_columns(table_name, column_type, *args)
        @table_column_type ||= {}
        @table_column_type[table_name] ||= {}
        args.each do |col|
          @table_column_type[table_name][col.to_s.downcase] = column_type
        end
      end
      
      def get_type_for_column(table_name, column_name)
        @table_column_type && @table_column_type[table_name] && @table_column_type[table_name][column_name.to_s.downcase]
      end

      def clear_types_for_columns
        @table_column_type = nil
      end

      def columns(table_name, name = nil) #:nodoc:
        # RSI: get ignored_columns by original table name
        ignored_columns = ignored_table_columns(table_name)

        (owner, desc_table_name) = @connection.describe(table_name)

        table_cols = <<-SQL
          select column_name as name, data_type as sql_type, data_default, nullable,
                 decode(data_type, 'NUMBER', data_precision,
                                   'FLOAT', data_precision,
                                   'VARCHAR2', data_length,
                                   'CHAR', data_length,
                                    null) as limit,
                 decode(data_type, 'NUMBER', data_scale, null) as scale
            from all_tab_columns
           where owner      = '#{owner}'
             and table_name = '#{desc_table_name}'
           order by column_id
        SQL

        # RSI: added deletion of ignored columns
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
                           # RSI: pass table name for table specific column definitions
                           table_name,
                           # RSI: pass column type if specified in class definition
                           get_type_for_column(table_name, oracle_downcase(row['name'])))
        end
      end

      # RSI: default sequence start with value
      @@default_sequence_start_value = 10000
      cattr_accessor :default_sequence_start_value

      def create_table(name, options = {}, &block) #:nodoc:
        create_sequence = options[:id] != false
        column_comments = {}
        super(name, options) do |t|
          # store that primary key was defined in create_table block
          unless create_sequence
            class <<t
              attr_accessor :create_sequence
              def primary_key(*args)
                self.create_sequence = true
                super(*args)
              end
            end
          end

          # store column comments
          class <<t
            attr_accessor :column_comments
            def column(name, type, options = {})
              if options[:comment]
                self.column_comments ||= {}
                self.column_comments[name] = options[:comment]
              end
              super(name, type, options)
            end
          end

          result = block.call(t)
          create_sequence = create_sequence || t.create_sequence
          column_comments = t.column_comments if t.column_comments
        end

        seq_name = options[:sequence_name] || quote_table_name("#{name}_seq")
        seq_start_value = options[:sequence_start_value] || default_sequence_start_value
        execute "CREATE SEQUENCE #{seq_name} START WITH #{seq_start_value}" if create_sequence
        
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
        seq_name = options[:sequence_name] || quote_table_name("#{name}_seq")
        execute "DROP SEQUENCE #{seq_name}" rescue nil
      end

      # clear cached indexes when adding new index
      def add_index(table_name, column_name, options = {})
        self.all_schema_indexes = nil
        super
      end

      # clear cached indexes when removing index
      def remove_index(table_name, options = {}) #:nodoc:
        self.all_schema_indexes = nil
        execute "DROP INDEX #{index_name(table_name, options)}"
      end

      def add_column(table_name, column_name, type, options = {})
        add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        options[:type] = type
        add_column_options!(add_column_sql, options)
        execute(add_column_sql)
      end

      def change_column_default(table_name, column_name, default) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} DEFAULT #{quote(default)}"
      end

      def change_column_null(table_name, column_name, null, default = nil)
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
      end

      def rename_column(table_name, column_name, new_column_name) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}"
      end

      def remove_column(table_name, column_name) #:nodoc:
        execute "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)}"
      end

      # RSI: table and column comments
      def add_comment(table_name, column_name, comment)
        return if comment.blank?
        execute "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{column_name} IS '#{comment}'"
      end

      def add_table_comment(table_name, comment)
        return if comment.blank?
        execute "COMMENT ON TABLE #{quote_table_name(table_name)} IS '#{comment}'"
      end

      def table_comment(table_name)
        (owner, table_name) = @connection.describe(table_name)
        select_value <<-SQL
          SELECT comments FROM all_tab_comments
          WHERE owner = '#{owner}'
            AND table_name = '#{table_name}'
        SQL
      end

      def column_comment(table_name, column_name)
        (owner, table_name) = @connection.describe(table_name)
        select_value <<-SQL
          SELECT comments FROM all_col_comments
          WHERE owner = '#{owner}'
            AND table_name = '#{table_name}'
            AND column_name = '#{column_name.upcase}'
        SQL
      end

      # Find a table's primary key and sequence. 
      # *Note*: Only primary key is implemented - sequence will be nil.
      def pk_and_sequence_for(table_name)
        (owner, table_name) = @connection.describe(table_name)

        # RSI: changed select from all_constraints to user_constraints - much faster in large data dictionaries
        pks = select_values(<<-SQL, 'Primary Key')
          select cc.column_name
            from user_constraints c, user_cons_columns cc
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
          structure << "create sequence #{seq.to_a.first.last};\n\n"
        end

        # RSI: changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') order by 1").inject(s) do |structure, table|
          ddl = "create table #{table.to_a.first.last} (\n "
          cols = select_all(%Q{
            select column_name, data_type, data_length, char_used, char_length, data_precision, data_scale, data_default, nullable
            from user_tab_columns
            where table_name = '#{table.to_a.first.last}'
            order by column_id
          }).map do |row|
            col = "#{row['column_name'].downcase} #{row['data_type'].downcase}"
            if row['data_type'] =='NUMBER' and !row['data_precision'].nil?
              col << "(#{row['data_precision'].to_i}"
              col << ",#{row['data_scale'].to_i}" if !row['data_scale'].nil?
              col << ')'
            elsif row['data_type'].include?('CHAR')
              length = row['char_used'] == 'C' ? row['char_length'].to_i : row['data_length'].to_i
              col <<  "(#{length})"
            end
            col << " default #{row['data_default']}" if !row['data_default'].nil?
            col << ' not null' if row['nullable'] == 'N'
            col
          end
          ddl << cols.join(",\n ")
          ddl << ");\n\n"
          structure << ddl
        end
      end

      def structure_drop #:nodoc:
        s = select_all("select sequence_name from user_sequences order by 1").inject("") do |drop, seq|
          drop << "drop sequence #{seq.to_a.first.last};\n\n"
        end

        # RSI: changed select from user_tables to all_tables - much faster in large data dictionaries
        select_all("select table_name from all_tables where owner = sys_context('userenv','session_user') order by 1").inject(s) do |drop, table|
          drop << "drop table #{table.to_a.first.last} cascade constraints;\n\n"
        end
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
      def distinct(columns, order_by)
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

      # ORDER BY clause for the passed order option.
      # 
      # Uses column aliases as defined by #distinct.
      def add_order_by_for_association_limiting!(sql, options)
        return sql if options[:order].blank?

        order = options[:order].split(',').collect { |s| s.strip }.reject(&:blank?)
        order.map! {|s| $1 if s =~ / (.*)/}
        order = order.zip((0...order.size).to_a).map { |s,i| "alias_#{i}__ #{s}" }.join(', ')

        sql << " ORDER BY #{order}"
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

    end
  end
end

# RSI: Added LOB writing callback for sessions stored in database
# Otherwise it is not working as Session class is defined before OracleAdapter is loaded in Rails 2.0
if defined?(CGI::Session::ActiveRecordStore::Session)
  if !CGI::Session::ActiveRecordStore::Session.respond_to?(:after_save_callback_chain) ||
      CGI::Session::ActiveRecordStore::Session.after_save_callback_chain.detect{|cb| cb.method == :enhanced_write_lobs}.nil?
    class CGI::Session::ActiveRecordStore::Session
      after_save :enhanced_write_lobs
    end
  end
end

# RSI: load custom create, update, delete methods functionality
# rescue LoadError if ruby-plsql gem cannot be loaded
begin
  require 'active_record/connection_adapters/oracle_enhanced_procedures'
rescue LoadError
  if defined?(RAILS_DEFAULT_LOGGER)
    RAILS_DEFAULT_LOGGER.info "INFO: ActiveRecord oracle_enhanced adapter could not load ruby-plsql gem. "+
                              "Custom create, update and delete methods will not be available."
  end
end

# RSI: load additional methods for composite_primary_keys support
require 'active_record/connection_adapters/oracle_enhanced_cpk'

# RSI: load patch for dirty tracking methods
require 'active_record/connection_adapters/oracle_enhanced_dirty'

# RSI: load rake tasks definitions
begin
  require 'active_record/connection_adapters/oracle_enhanced_tasks'
rescue LoadError
end if defined?(RAILS_ROOT)

# handles quoting of oracle reserved words
require 'active_record/connection_adapters/oracle_enhanced_reserved_words'

# add BigDecimal#to_d, Fixnum#to_d and Bignum#to_d methods if not already present
require 'active_record/connection_adapters/oracle_enhanced_core_ext'

