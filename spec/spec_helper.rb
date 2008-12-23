require 'rubygems'
gem 'rspec'
require 'spec'

$:.unshift(File.dirname(__FILE__) + '/../lib')
# gem 'activerecord', '=2.0.2'
# gem 'actionpack', '=2.0.2'
# gem 'activesupport', '=2.0.2'
# gem 'composite_primary_keys', '=0.9.93'

# gem 'activerecord', '=2.1.2'
# gem 'actionpack', '=2.1.2'
# gem 'activesupport', '=2.1.2'
# gem 'composite_primary_keys', '=1.0.8'

gem 'activerecord', '=2.2.2'
gem 'actionpack', '=2.2.2'
gem 'activesupport', '=2.2.2'
gem 'composite_primary_keys', '=2.2.0'

require 'activerecord'
require 'actionpack'
require 'action_controller/session/active_record_store'
require 'active_record/connection_adapters/oracle_enhanced_adapter'
gem "activerecord-oracle-adapter"
require 'active_record/connection_adapters/oracle_adapter'
