# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        # A behavior applies to migrations declaring its own version and older:
        # Migration[8.2]+ resolves to V8_2, Migration[8.1] and earlier to V8_1.
        class V8_2 < Base; end
        class V8_1 < V8_2; end
      end
    end
  end
end
