if defined?(Rails)
  module ActiveRecord
    module ConnectionAdapters
      class OracleEnhancedRailtie < ::Rails::Railtie
        rake_tasks do
          load 'active_record/connection_adapters/oracle_enhanced/database_tasks.rb'
        end

        ActiveSupport.on_load(:active_record) do
          require 'active_record/connection_adapters/oracle_enhanced_adapter'

          # Cache column descriptions between requests in test and production environments
          if Rails.env.test? || Rails.env.production?
            ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
          end

        end

      end
    end
  end
end
