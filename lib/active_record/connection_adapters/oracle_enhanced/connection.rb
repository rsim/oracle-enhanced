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

        attr_reader :raw_connection, :owner
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
