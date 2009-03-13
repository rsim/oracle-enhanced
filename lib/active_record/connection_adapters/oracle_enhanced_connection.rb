module ActiveRecord
  module ConnectionAdapters
    # interface independent methods
    class OracleEnhancedConnection

      def self.create(config)
        case ORACLE_ENHANCED_CONNECTION
        when :oci
          OracleEnhancedOCIConnection.new(config)
        when :jdbc
          OracleEnhancedJDBCConnection.new(config)
        else
          nil
        end
      end

      attr_reader :raw_connection

      # Oracle column names by default are case-insensitive, but treated as upcase;
      # for neatness, we'll downcase within Rails. EXCEPT that folks CAN quote
      # their column names when creating Oracle tables, which makes then case-sensitive.
      # I don't know anybody who does this, but we'll handle the theoretical case of a
      # camelCase column name. I imagine other dbs handle this different, since there's a
      # unit test that's currently failing test_oci.
      def oracle_downcase(column_name)
        column_name =~ /[a-z]/ ? column_name : column_name.downcase
      end

      private
      
      # Returns a record hash with the column names as keys and column values
      # as values.
      def select_one(sql)
        result = select(sql)
        result.first if result
      end

      # Returns a single value from a record
      def select_value(sql)
        if result = select_one(sql)
          result.values.first
        end
      end

      # Returns an array of the values of the first column in a select:
      #   select_values("SELECT id FROM companies LIMIT 3") => [1,2,3]
      def select_values(sql)
        result = select(sql)
        result.map { |r| r.values.first }
      end
      

    end
    
    class OracleEnhancedConnectionException < StandardError
    end

  end
end

# if MRI or YARV
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == 'ruby'
  ORACLE_ENHANCED_CONNECTION = :oci
  require 'active_record/connection_adapters/oracle_enhanced_oci_connection'
# if JRuby
elsif RUBY_ENGINE == 'jruby'
  ORACLE_ENHANCED_CONNECTION = :jdbc
  require 'active_record/connection_adapters/oracle_enhanced_jdbc_connection'
else
  raise "Unsupported Ruby engine #{RUBY_ENGINE}"
end
