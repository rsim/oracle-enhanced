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
else
  ENV['RAILS_GEM_VERSION'] ||= '2.3.2'
  gem 'activerecord', '=2.3.2'
  gem 'actionpack', '=2.3.2'
  gem 'activesupport', '=2.3.2'
  gem 'composite_primary_keys', '=2.2.2'
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
  gem "activerecord-oracle-adapter"
  require 'active_record/connection_adapters/oracle_adapter'
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

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => "xe",
  :host => "ubuntu810",
  :username => "hr",
  :password => "hr"
}

JDBC_CONNECTION_PARAMS = {
  :adapter => "jdbc",
  :driver => "oracle.jdbc.driver.OracleDriver",
  :url => "jdbc:oracle:thin:@ubuntu810:1521:XE",
  :username => "hr",
  :password => "hr"
}

SYS_CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => "xe",
  :host => "ubuntu810",
  :username => "sys",
  :password => "manager",
  :privilege => "SYSDBA"
}

# For JRuby Set default $KCODE to UTF8
$KCODE = "UTF8" if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
