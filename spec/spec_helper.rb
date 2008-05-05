begin
  require 'spec'
rescue LoadError
  require 'rubygems'
  gem 'rspec'
  require 'spec'
end

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'activerecord'
require 'actionpack'
require 'action_controller/session/active_record_store'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
gem "activerecord-oracle-adapter"
require 'active_record/connection_adapters/oracle_adapter'
