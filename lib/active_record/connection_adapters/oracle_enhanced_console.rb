begin
  require 'io/console'
rescue LoadError
end

module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter

      class Console

        def self.query_secret(prompt)
          make.query_secret(prompt)
        end

        def self.make
          if capable?
            new
          else
            LegacyConsole.new
          end
        end

        def self.capable?
          $stdin.respond_to?(:noecho)
        end

        def query_secret(prompt)
          $stdout.puts prompt
          $stdout.print ">"
          $stdout.flush
          $stdin.noecho(&:gets).chomp.tap do
            $stdout.puts
          end
        end

      end

      class LegacyConsole

        def query_secret(prompt)
          $stdout.puts prompt
          $stdout.puts "WARNING: Password will echo"
          $stdout.print ">"
          $stdout.flush
          $stdin.gets.chomp
        end

      end

    end
  end
end
