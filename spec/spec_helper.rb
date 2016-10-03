require "rubygems"
require "bundler"
require "yaml"
Bundler.setup(:default, :development)

$:.unshift(File.expand_path('../../lib', __FILE__))
config_path = File.expand_path('../spec_config.yaml', __FILE__)
if File.exist?(config_path)
  puts "==> Loading config from #{config_path}"
  config = YAML.load_file(config_path)
else
  puts "==> Loading config from ENV or use default"
  config = {"rails" => {}, "database" => {}}
end

require 'rspec'

if !defined?(RUBY_ENGINE) || RUBY_ENGINE == 'ruby'
  puts "==> Running specs with MRI version #{RUBY_VERSION}"
  require 'oci8'
elsif RUBY_ENGINE == 'jruby'
  puts "==> Running specs with JRuby version #{JRUBY_VERSION}"
end

NO_COMPOSITE_PRIMARY_KEYS = true

require 'active_record'

require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/class/attribute_accessors'

require "active_support/log_subscriber"
require 'active_record/log_subscriber'

require 'logger'

require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'ruby-plsql'

puts "==> Effective ActiveRecord version #{ActiveRecord::VERSION::STRING}"

module LoggerSpecHelper
  def set_logger
    @logger = MockLogger.new
    @old_logger = ActiveRecord::Base.logger

    @notifier = ActiveSupport::Notifications::Fanout.new

    ActiveSupport::LogSubscriber.colorize_logging = false

    ActiveRecord::Base.logger = @logger
    @old_notifier = ActiveSupport::Notifications.notifier
    ActiveSupport::Notifications.notifier = @notifier

    ActiveRecord::LogSubscriber.attach_to(:active_record)
    ActiveSupport::Notifications.subscribe("sql.active_record", ActiveRecord::ExplainSubscriber.new)
  end

  class MockLogger
    attr_reader :flush_count

    def initialize
      @flush_count = 0
      @logged = Hash.new { |h,k| h[k] = [] }
    end

    # used in AtiveRecord 2.x
    def debug?
      true
    end

    def method_missing(level, message)
      @logged[level] << message
    end

    def logged(level)
      @logged[level].compact.map { |l| l.to_s.strip }
    end

    def output(level)
      logged(level).join("\n")
    end

    def flush
      @flush_count += 1
    end

    def clear(level)
      @logged[level] = []
    end
  end

  def clear_logger
    ActiveRecord::Base.logger = @old_logger
    @logger = nil

    ActiveSupport::Notifications.notifier = @old_notifier
    @notifier = nil
  end

  # Wait notifications to be published (for Rails 3.0)
  # should not be currently used with sync queues in tests
  def wait
    @notifier.wait if @notifier
  end

end

module SchemaSpecHelper
  def schema_define(&block)
    ActiveRecord::Schema.define do
      suppress_messages do
        instance_eval(&block)
      end
    end
  end
end

DATABASE_NAME         = config["database"]["name"]         || ENV['DATABASE_NAME']         || 'orcl'
DATABASE_HOST         = config["database"]["host"]         || ENV['DATABASE_HOST']         || "127.0.0.1"
DATABASE_PORT         = config["database"]["port"]         || ENV['DATABASE_PORT']         || 1521
DATABASE_USER         = config["database"]["user"]         || ENV['DATABASE_USER']         || 'oracle_enhanced'
DATABASE_PASSWORD     = config["database"]["password"]     || ENV['DATABASE_PASSWORD']     || 'oracle_enhanced'
DATABASE_SCHEMA       = config["database"]["schema"]       || ENV['DATABASE_SCHEMA']       || 'oracle_enhanced_schema'
DATABASE_SYS_PASSWORD = config["database"]["sys_password"] || ENV['DATABASE_SYS_PASSWORD'] || 'admin'

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD
}

CONNECTION_WITH_SCHEMA_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD,
  :schema => DATABASE_SCHEMA
}

CONNECTION_WITH_TIMEZONE_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD,
  :time_zone => "Europe/Riga"
}

SYS_CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => "sys",
  :password => DATABASE_SYS_PASSWORD,
  :privilege => "SYSDBA"
}

SYSTEM_CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => "system",
  :password => DATABASE_SYS_PASSWORD
}

DATABASE_NON_DEFAULT_TABLESPACE = config["database"]["non_default_tablespace"] || ENV['DATABASE_NON_DEFAULT_TABLESPACE'] || "SYSTEM"

# set default time zone in TZ environment variable
# which will be used to set session time zone
ENV['TZ'] ||= config["timezone"] || 'Europe/Riga'

# ActiveRecord::Base.logger = Logger.new(STDOUT)
