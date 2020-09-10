# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # interface independent methods
    module OracleEnhanced
      class Connection #:nodoc:
        def self.create(config)
          case ORACLE_ENHANCED_CONNECTION
          when :oci
            OracleEnhanced::OCIConnection.new(config)
          when :jdbc
            OracleEnhanced::JDBCConnection.new(config)
          else
            nil
          end
        end

        attr_reader :raw_connection

        private
          # Used always by JDBC connection as well by OCI connection when describing tables over database link
          def describe(name)
            name = name.to_s
            if name.include?("@")
              raise ArgumentError "db link is not supported"
            else
              default_owner = @owner
            end
            real_name = OracleEnhanced::Quoting.valid_table_name?(name) ? name.upcase : name
            if real_name.include?(".")
              table_owner, table_name = real_name.split(".")
            else
              table_owner, table_name = default_owner, real_name
            end
            sql = <<~SQL.squish
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
            if result = _select_one(sql)
              case result["name_type"]
              when "SYNONYM"
                describe("#{result['owner'] && "#{result['owner']}."}#{result['table_name']}")
              else
                [result["owner"], result["table_name"]]
              end
            else
              raise OracleEnhanced::ConnectionException, %Q{"DESC #{name}" failed; does it exist?}
            end
          end

          # Oracle column names by default are case-insensitive, but treated as upcase;
          # for neatness, we'll downcase within Rails. EXCEPT that folks CAN quote
          # their column names when creating Oracle tables, which makes then case-sensitive.
          # I don't know anybody who does this, but we'll handle the theoretical case of a
          # camelCase column name. I imagine other dbs handle this different, since there's a
          # unit test that's currently failing test_oci.
          #
          # `_oracle_downcase` is expected to be called only from
          # `ActiveRecord::ConnectionAdapters::OracleEnhanced::OCIConnection`
          # or `ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection`.
          # Other method should call `ActiveRecord:: ConnectionAdapters::OracleEnhanced::Quoting#oracle_downcase`
          # since this is kind of quoting, not connection.
          # To avoid it is called from anywhere else, added _ at the beginning of the method name.
          def _oracle_downcase(column_name)
            return nil if column_name.nil?
            /[a-z]/.match?(column_name) ? column_name : column_name.downcase
          end

          # _select_one and _select_value methods are expected to be called
          # only from `ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection#describe`
          # Other methods should call `ActiveRecord::ConnectionAdapters::DatabaseStatements#select_one`
          # and  `ActiveRecord::ConnectionAdapters::DatabaseStatements#select_value`
          # To avoid called from its subclass added a underscore in each method.

          # Returns a record hash with the column names as keys and column values
          # as values.
          def _select_one(arel, name = nil, binds = [])
            result = select(arel)
            result.first if result
          end

          # Returns a single value from a record
          def _select_value(arel, name = nil, binds = [])
            if result = _select_one(arel)
              result.values.first
            end
          end
      end

      # Returns array with major and minor version of database (e.g. [12, 1])
      def database_version
        raise NoMethodError, "Not implemented for this raw driver"
      end
      class ConnectionException < StandardError #:nodoc:
      end
    end
  end
end

# if MRI or YARV or TruffleRuby
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby" || RUBY_ENGINE == "truffleruby"
  ORACLE_ENHANCED_CONNECTION = :oci
  require "active_record/connection_adapters/oracle_enhanced/oci_connection"
# if JRuby
elsif RUBY_ENGINE == "jruby"
  ORACLE_ENHANCED_CONNECTION = :jdbc
  require "active_record/connection_adapters/oracle_enhanced/jdbc_connection"
else
  raise "Unsupported Ruby engine #{RUBY_ENGINE}"
end
