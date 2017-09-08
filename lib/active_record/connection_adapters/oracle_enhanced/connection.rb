# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # interface independent methods
    class OracleEnhancedConnection #:nodoc:
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
        return nil if column_name.nil?
        column_name =~ /[a-z]/ ? column_name : column_name.downcase
      end

      # Used always by JDBC connection as well by OCI connection when describing tables over database link
      def describe(name)
        name = name.to_s
        if name.include?("@")
          raise ArgumentError "db link is not supported"
        else
          default_owner = @owner
        end
        real_name = ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting.valid_table_name?(name) ? name.upcase : name
        if real_name.include?(".")
          table_owner, table_name = real_name.split(".")
        else
          table_owner, table_name = default_owner, real_name
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
          SELECT table_owner, DECODE(db_link, NULL, table_name, table_name||'@'||db_link), 'SYNONYM' name_type
          FROM all_synonyms
          WHERE owner = '#{table_owner}'
            AND synonym_name = '#{table_name}'
          UNION ALL
          SELECT table_owner, DECODE(db_link, NULL, table_name, table_name||'@'||db_link), 'SYNONYM' name_type
          FROM all_synonyms
          WHERE owner = 'PUBLIC'
            AND synonym_name = '#{real_name}'
        SQL
        if result = select_one(sql)
          case result["name_type"]
          when "SYNONYM"
            describe("#{result['owner'] && "#{result['owner']}."}#{result['table_name']}")
          else
            [result["owner"], result["table_name"]]
          end
        else
          raise OracleEnhancedConnectionException, %Q{"DESC #{name}" failed; does it exist?}
        end
      end

      # Returns a record hash with the column names as keys and column values
      # as values.
      def select_one(arel, name = nil, binds = [])
        result = select(arel)
        result.first if result
      end

      # Returns a single value from a record
      def select_value(arel, name = nil, binds = [])
        if result = select_one(arel)
          result.values.first
        end
      end

      # Returns an array of the values of the first column in a select:
      #   select_values("SELECT id FROM companies LIMIT 3") => [1,2,3]
      def select_values(arel, name = nil, binds = [])
        result = select(arel, name = nil)
        result.map { |r| r.values.first }
      end
    end

    # Returns array with major and minor version of database (e.g. [12, 1])
    def database_version
      raise NoMethodError, "Not implemented for this raw driver"
    end

    class OracleEnhancedConnectionException < StandardError #:nodoc:
    end
  end
end

# if MRI or YARV
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby"
  ORACLE_ENHANCED_CONNECTION = :oci
  require "active_record/connection_adapters/oracle_enhanced/oci_connection"
# if JRuby
elsif RUBY_ENGINE == "jruby"
  ORACLE_ENHANCED_CONNECTION = :jdbc
  require "active_record/connection_adapters/oracle_enhanced/jdbc_connection"
else
  raise "Unsupported Ruby engine #{RUBY_ENGINE}"
end
