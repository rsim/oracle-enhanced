require 'rubygems'
require "bundler"
Bundler.setup(:default, :development)

$:.unshift(File.expand_path('../../lib', __FILE__))

require 'rspec'

if !defined?(RUBY_ENGINE) || RUBY_ENGINE == 'ruby'
  puts "==> Running specs with MRI version #{RUBY_VERSION}"
  require 'oci8'
elsif RUBY_ENGINE == 'jruby'
  puts "==> Running specs with JRuby version #{JRUBY_VERSION}"
end

ENV['RAILS_GEM_VERSION'] ||= '4.0-master'
NO_COMPOSITE_PRIMARY_KEYS = true

puts "==> Running specs with Rails version #{ENV['RAILS_GEM_VERSION']}"

require 'active_record'

require 'action_dispatch'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/class/attribute_accessors'

require "active_support/log_subscriber"
require 'active_record/log_subscriber'

require 'logger'

require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'ruby-plsql'

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

DATABASE_NAME = ENV['DATABASE_NAME'] || 'orcl'
DATABASE_HOST = ENV['DATABASE_HOST']
DATABASE_PORT = ENV['DATABASE_PORT']
DATABASE_USER = ENV['DATABASE_USER'] || 'oracle_enhanced'
DATABASE_PASSWORD = ENV['DATABASE_PASSWORD'] || 'oracle_enhanced'
DATABASE_SYS_PASSWORD = ENV['DATABASE_SYS_PASSWORD'] || 'admin'

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD
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

DATABASE_NON_DEFAULT_TABLESPACE = ENV['DATABASE_NON_DEFAULT_TABLESPACE'] || "SYSTEM"

# set default time zone in TZ environment variable
# which will be used to set session time zone
ENV['TZ'] ||= 'Europe/Riga'

# ActiveRecord::Base.logger = Logger.new(STDOUT)

# Set default_timezone :local explicitly 
# because this default value has been changed to :utc atrails master branch 
ActiveRecord::Base.default_timezone = :local

