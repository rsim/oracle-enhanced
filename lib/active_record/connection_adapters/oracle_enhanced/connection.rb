# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # interface independent methods
    module OracleEnhanced
      class Connection # :nodoc:
        class << self
          attr_accessor :connection_class
        end

        def self.create(config)
          connection_class&.new(config)
        end

        attr_reader :raw_connection
      end

      # Returns array with major and minor version of database (e.g. [12, 1])
      def database_version
        raise NoMethodError, "Not implemented for this raw driver"
      end
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
