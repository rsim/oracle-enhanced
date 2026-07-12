# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        extend Migration::CompatibilityBehavior::Resolver

        class V8_1 < Migration::CompatibilityBehavior; end
      end
    end
  end
end
