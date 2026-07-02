# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module CompatibilityBehavior # :nodoc: all
        extend Migration::CompatibilityBehavior::Resolver

        # Migration[8.1] and earlier keep the pre-8.2 sequence-backed primary
        # key default so existing migrations replay unchanged. An explicit
        # `identity:` value always wins.
        class V8_1 < Migration::CompatibilityBehavior
          def create_table(table_name, **options)
            options[:identity] = false unless options.key?(:identity)
            super
          end
        end
      end
    end
  end
end
