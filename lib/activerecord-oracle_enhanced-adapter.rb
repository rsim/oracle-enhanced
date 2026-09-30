# frozen_string_literal: true

if defined?(Rails)
  require "active_record/connection_adapters/oracle_enhanced/deprecator"

  module ActiveRecord
    module ConnectionAdapters
      class OracleEnhancedRailtie < ::Rails::Railtie
        initializer "oracle_enhanced.deprecator", before: :load_environment_config do |app|
          app.deprecators[:oracle_enhanced] = ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator
        end

        rake_tasks do
          load "active_record/connection_adapters/oracle_enhanced/database_tasks.rb"
        end

        ActiveSupport.on_load(:active_record) do
          require "active_record/connection_adapters/oracle_enhanced_adapter"

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
