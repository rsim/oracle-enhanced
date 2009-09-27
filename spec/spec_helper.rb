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
else
  ENV['RAILS_GEM_VERSION'] ||= '2.3.4'
  gem 'activerecord', '=2.3.4'
  gem 'actionpack', '=2.3.4'
  gem 'activesupport', '=2.3.4'
  NO_COMPOSITE_PRIMARY_KEYS = true
end

require 'activerecord'
require 'actionpack'
if ENV['RAILS_GEM_VERSION'] >= '2.3'
  require 'action_controller/session/abstract_store'
  require 'active_record/session_store'
else
  require 'action_controller/session/active_record_store'
end
if !defined?(RUBY_ENGINE)
  # change version to 1.0.6 to test with old oracle_adapter
  gem 'ruby-oci8', '>=2.0.2'
  require 'oci8'
  if OCI8::VERSION =~ /^1\./
    gem "activerecord-oracle-adapter"
    require 'active_record/connection_adapters/oracle_adapter'
  end
elsif RUBY_ENGINE == 'ruby'
  gem 'ruby-oci8', '>=2.0.2'
  require 'oci8'
elsif RUBY_ENGINE == 'jruby'
  gem "activerecord-jdbc-adapter"
  require 'active_record/connection_adapters/jdbc_adapter'
end

require 'active_record/connection_adapters/oracle_enhanced_adapter'

module LoggerSpecHelper
  def log_to(stream)
    ActiveRecord::Base.logger = Logger.new(stream)
    if ActiveRecord::Base.respond_to?(:connection_pool)
      ActiveRecord::Base.connection_pool.clear_reloadable_connections!
    else
      ActiveRecord::Base.clear_active_connections!
    end
    ActiveRecord::Base.colorize_logging = false
    ActiveRecord::Base.logger.level = Logger::DEBUG
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
DATABASE_USER = ENV['DATABASE_USER'] || 'hr'
DATABASE_PASSWORD = ENV['DATABASE_PASSWORD'] || 'hr'
DATABASE_SYS_PASSWORD = ENV['DATABASE_SYS_PASSWORD'] || 'admin'

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD
}

JDBC_CONNECTION_PARAMS = {
  :adapter => "jdbc",
  :driver => "oracle.jdbc.driver.OracleDriver",
  :url => "jdbc:oracle:thin:@#{DATABASE_HOST}:#{DATABASE_PORT}:#{DATABASE_NAME}",
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
