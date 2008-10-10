require 'rubygems'
gem 'rspec'
require 'spec'

$:.unshift(File.dirname(__FILE__) + '/../lib')
# gem 'activerecord', '=2.0.2'
# gem 'actionpack', '=2.0.2'
# gem 'activesupport', '=2.0.2'
gem 'activerecord', '=2.1.1'
gem 'actionpack', '=2.1.1'
gem 'activesupport', '=2.1.1'
require 'activerecord'
require 'actionpack'
require 'action_controller/session/active_record_store'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
gem "activerecord-oracle-adapter"
require 'active_record/connection_adapters/oracle_adapter'
