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

ENV['RAILS_GEM_VERSION'] ||= '3.1-master'
NO_COMPOSITE_PRIMARY_KEYS = true if ENV['RAILS_GEM_VERSION'] >= '2.3.5'

puts "==> Running specs with Rails version #{ENV['RAILS_GEM_VERSION']}"

require 'active_record'

if ENV['RAILS_GEM_VERSION'] >= '3.0'
  require 'action_dispatch'
  require 'active_support/core_ext/module/attribute_accessors'

  if ENV['RAILS_GEM_VERSION'] =~ /^3.0.0.beta/
    require "rails/log_subscriber"
    require 'active_record/railties/log_subscriber'
  else
    require "active_support/log_subscriber"
    require 'active_record/log_subscriber'
  end

  require 'logger'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.3/
  require 'action_pack'
  require 'action_controller/session/abstract_store'
  require 'active_record/session_store'
elsif ENV['RAILS_GEM_VERSION'] <= '2.3'
  require 'action_pack'
  require 'action_controller/session/active_record_store'
end

require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'ruby-plsql'

module LoggerSpecHelper
  def set_logger
    @logger = MockLogger.new
    @old_logger = ActiveRecord::Base.logger

    if ENV['RAILS_GEM_VERSION'] =~ /^3.0.0.beta/
      queue = ActiveSupport::Notifications::Fanout.new
      @notifier = ActiveSupport::Notifications::Notifier.new(queue)

      Rails::LogSubscriber.colorize_logging = false

      ActiveRecord::Base.logger = @logger
      @old_notifier = ActiveSupport::Notifications.notifier
      ActiveSupport::Notifications.notifier = @notifier

      Rails::LogSubscriber.add(:active_record, ActiveRecord::Railties::LogSubscriber.new)

    elsif ENV['RAILS_GEM_VERSION'] >= '3.0'
      @notifier = ActiveSupport::Notifications::Fanout.new

      ActiveSupport::LogSubscriber.colorize_logging = false

      ActiveRecord::Base.logger = @logger
      @old_notifier = ActiveSupport::Notifications.notifier
      ActiveSupport::Notifications.notifier = @notifier

      ActiveRecord::LogSubscriber.attach_to(:active_record)

    else # ActiveRecord 2.x
      if ActiveRecord::Base.respond_to?(:connection_pool)
        ActiveRecord::Base.connection_pool.clear_reloadable_connections!
      else
        ActiveRecord::Base.clear_active_connections!
      end
      ActiveRecord::Base.logger = @logger
      ActiveRecord::Base.colorize_logging = false
      # ActiveRecord::Base.logger.level = Logger::DEBUG
    end

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

    if ENV['RAILS_GEM_VERSION'] >= '3.0'
      ActiveSupport::Notifications.notifier = @old_notifier
      @notifier = nil
    end

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

# Set default $KCODE to UTF8
$KCODE = "UTF8"

# set default time zone in TZ environment variable
# which will be used to set session time zone
ENV['TZ'] ||= 'Europe/Riga'
