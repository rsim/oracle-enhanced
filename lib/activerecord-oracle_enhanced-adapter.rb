# frozen_string_literal: true

if defined?(Rails)
  module ActiveRecord
    module ConnectionAdapters
      class OracleEnhancedRailtie < ::Rails::Railtie
        rake_tasks do
          load "active_record/connection_adapters/oracle_enhanced/database_tasks.rb"
        end

        ActiveSupport.on_load(:active_record) do
          require "active_record/connection_adapters/oracle_enhanced_adapter"

          if ActiveRecord::ConnectionAdapters.respond_to?(:register)
            ActiveRecord::ConnectionAdapters.register(
              "oracle_enhanced",
              "ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter",
              "active_record/connection_adapters/oracle_enhanced_adapter"
            )
          end
        end
      end
    end
  end
end
