# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # interface independent methods
    module OracleEnhanced
      class Connection # :nodoc:
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
          # POC: resolve object name via DBMS_UTILITY.NAME_RESOLVE instead of
          # querying all_tables / all_views / all_synonyms. NAME_RESOLVE follows
          # private and public synonyms for us, so no manual recursion is needed.
          # See https://github.com/rsim/oracle-enhanced/pull/2521#issuecomment-4242585736
          def describe(name)
            name = name.to_s
            if name.include?("@")
              raise ArgumentError, "db link is not supported"
            end
            if OracleEnhanced::Quoting.valid_table_name?(name)
              _resolve_name(name.upcase)
            else
              # Per-part normalization so that e.g. "sys.test_Mixed" becomes
              # SYS."test_Mixed" — quoting a schema that's actually upcase
              # internally would make Oracle search for a lowercase schema
              # and miss it.
              parts = name.split(".").map do |p|
                OracleEnhanced::Quoting.valid_table_name?(p) ? p.upcase : %("#{p}")
              end
              _resolve_name(parts.join("."))
            end
          rescue OracleEnhanced::ConnectionException, ArgumentError
            raise
          rescue => e
            raise OracleEnhanced::ConnectionException, %Q{"DESC #{name}" failed; does it exist? (#{e.message})}
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
          # binds is a array of native values in contrast to ActiveRecord::Relation::QueryAttribute
          def _select_one(arel, name = nil, binds = [])
            cursor = prepare(arel)
            cursor.bind_params(binds)
            cursor.exec
            columns = cursor.get_col_names.map do |col_name|
              _oracle_downcase(col_name)
            end
            row = cursor.fetch
            columns.each_with_index.to_h { |x, i| [x, row[i]] } if row
          ensure
            cursor.close
          end

          # Returns a single value from a record
          def _select_value(arel, name = nil, binds = [])
            if result = _select_one(arel, name, binds)
              result.values.first
            end
          end
      end

      # Returns array with major and minor version of database (e.g. [12, 1])
      def database_version
        raise NoMethodError, "Not implemented for this raw driver"
      end

      # ORA-00028 your session has been killed
      # ORA-01012 not logged on
      # ORA-03113 end-of-file on communication channel
      # ORA-03114 not connected to ORACLE
      # ORA-03135 connection lost contact
      LOST_CONNECTION_ERROR_CODES = [28, 1012, 3113, 3114, 3135] # :nodoc:

      class ConnectionException < StandardError # :nodoc:
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
