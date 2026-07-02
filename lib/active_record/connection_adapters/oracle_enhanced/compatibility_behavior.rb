# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        # A behavior covers migrations declaring its own version and older:
        # Migration[8.1] and earlier resolve to V8_1. Migration[8.2] and later
        # resolve to the no-op base, so the adapter's own defaults apply.

        # Migration[8.1] and earlier keep the pre-8.2 sequence-backed primary
        # key default so existing migrations replay unchanged. An explicit
        # `identity:` value always wins.
        class V8_1 < Base
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            super
          end
        end
      end
    end
  end
end
