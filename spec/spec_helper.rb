require 'rubygems'
gem 'rspec'
require 'spec'

$:.unshift(File.dirname(__FILE__) + '/../lib')

if ENV['RAILS_GEM_VERSION'] =~ /^2.0/
  gem 'activerecord', '=2.0.2'
  gem 'actionpack', '=2.0.2'
  gem 'activesupport', '=2.0.2'
  gem 'composite_primary_keys', '=0.9.93'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.1/
  gem 'activerecord', '=2.1.2'
  gem 'actionpack', '=2.1.2'
  gem 'activesupport', '=2.1.2'
  gem 'composite_primary_keys', '=1.0.8'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.2/
  gem 'activerecord', '=2.2.2'
  gem 'actionpack', '=2.2.2'
  gem 'activesupport', '=2.2.2'
  gem 'composite_primary_keys', '=2.2.2'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.3.3/
  gem 'activerecord', '=2.3.3'
  gem 'actionpack', '=2.3.3'
  gem 'activesupport', '=2.3.3'
  gem 'composite_primary_keys', '=2.3.2'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.3.5/
  gem 'activerecord', '=2.3.5'
  gem 'actionpack', '=2.3.5'
  gem 'activesupport', '=2.3.5'
  NO_COMPOSITE_PRIMARY_KEYS = true
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.3/
  gem 'activerecord', '=2.3.8'
  gem 'actionpack', '=2.3.8'
  gem 'activesupport', '=2.3.8'
  NO_COMPOSITE_PRIMARY_KEYS = true
else
  # uses local copy of Rails 3 gems
  ['rails/activerecord', 'rails/activemodel', 'rails/activesupport', 'arel', 'rails/actionpack', 'rails/railties'].each do |library|
    $:.unshift(File.expand_path(File.dirname(__FILE__) + '/../../' + library + '/lib'))
  end
  ENV['RAILS_GEM_VERSION'] ||= '3.0'
  NO_COMPOSITE_PRIMARY_KEYS = true
end

require 'active_record'

if ENV['RAILS_GEM_VERSION'] >= '3.0'
  require 'action_dispatch'
  require 'active_support/core_ext/module/attribute_accessors'
  require "rails/log_subscriber"
  require 'active_record/railties/log_subscriber'
  require 'logger'
elsif ENV['RAILS_GEM_VERSION'] =~ /^2.3/
  require 'action_pack'
  require 'action_controller/session/abstract_store'
  require 'active_record/session_store'
elsif ENV['RAILS_GEM_VERSION'] <= '2.3'
  require 'action_pack'
  require 'action_controller/session/active_record_store'
end
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == 'ruby'
  gem 'ruby-oci8', '>=2.0.4'
  require 'oci8'
elsif RUBY_ENGINE == 'jruby'
  gem 'activerecord-jdbc-adapter'
  require 'active_record/connection_adapters/jdbc_adapter'
end

require 'active_record/connection_adapters/oracle_enhanced_adapter'
require 'ruby-plsql'

module LoggerSpecHelper
  def set_logger
    @logger = MockLogger.new

    if ENV['RAILS_GEM_VERSION'] >= '3.0'
      queue = ActiveSupport::Notifications::Fanout.new
      @notifier = ActiveSupport::Notifications::Notifier.new(queue)

      Rails::LogSubscriber.colorize_logging = false

      ActiveRecord::Base.logger = @logger
      ActiveSupport::Notifications.notifier = @notifier

      Rails::LogSubscriber.add(:active_record, ActiveRecord::Railties::LogSubscriber.new)

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
    ActiveRecord::Base.logger = @logger = nil
    ActiveSupport::Notifications.notifier = @notifier = nil if @notifier
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
DATABASE_HOST = ENV['DATABASE_HOST'] || 'localhost'
DATABASE_PORT = ENV['DATABASE_PORT'] || 1521
DATABASE_USER = ENV['DATABASE_USER'] || 'oracle_enhanced'
DATABASE_PASSWORD = ENV['DATABASE_PASSWORD'] || 'oracle_enhanced'
DATABASE_SYS_PASSWORD = ENV['DATABASE_SYS_PASSWORD'] || 'admin'

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD
}

SYS_CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :username => "sys",
  :password => DATABASE_SYS_PASSWORD,
  :privilege => "SYSDBA"
}

SYSTEM_CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :username => "system",
  :password => DATABASE_SYS_PASSWORD
}

# For JRuby Set default $KCODE to UTF8
$KCODE = "UTF8" if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

# set default time zone in TZ environment variable
# which will be used to set session time zone
ENV['TZ'] ||= 'Europe/Riga'
