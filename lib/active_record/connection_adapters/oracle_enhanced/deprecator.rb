# frozen_string_literal: true

require "active_support/deprecation"

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      def self.deprecator # :nodoc:
        @deprecator ||= ActiveSupport::Deprecation.new("a future version", "activerecord-oracle_enhanced-adapter")
      end
    end
  end
end
