# frozen_string_literal: true

module ActiveRecord
  module Type
    module OracleEnhanced
      Json = ActiveSupport::Deprecation::DeprecatedConstantProxy.new(
        "ActiveRecord::Type::OracleEnhanced::Json",
        "ActiveRecord::Type::Json",
        ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator
      )
    end
  end
end
