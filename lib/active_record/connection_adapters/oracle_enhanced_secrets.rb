require 'active_record/connection_adapters/oracle_enhanced_console'

module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter

      module Secrets

        class Secret

          attr_accessor :environment_key
          attr_accessor :prompt

          def initialize
            yield self if block_given?
          end

          def get
            @value ||= get_from_environment || get_from_console
          end

          private

          def get_from_environment
            ENV[environment_key]
          end

          def get_from_console
            Console.query_secret(prompt)
          end

        end

        DATABASE_SYS_PASSWORD = Secret.new do |s|
          s.environment_key = "DATABASE_SYS_PASSWORD"
          s.prompt = "Please provide the SYSTEM password for your Oracle installation"
        end

      end  

    end
  end
end
