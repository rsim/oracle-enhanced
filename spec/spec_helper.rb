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
else
  gem 'activerecord', '=2.2.2'
  gem 'actionpack', '=2.2.2'
  gem 'activesupport', '=2.2.2'
  gem 'composite_primary_keys', '=2.2.0'
end

require 'activerecord'
require 'actionpack'
require 'action_controller/session/active_record_store'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
gem "activerecord-oracle-adapter"
require 'active_record/connection_adapters/oracle_adapter'

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