require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  gem.name = "activerecord-oracle_enhanced-adapter"
  gem.summary = "Oracle enhanced adapter for ActiveRecord"
  gem.description = <<-EOS
Oracle "enhanced" ActiveRecord adapter contains useful additional methods for working with new and legacy Oracle databases.
This adapter is superset of original ActiveRecord Oracle adapter.
EOS
  gem.email = "raimonds.simanovskis@gmail.com"
  gem.homepage = "http://github.com/rsim/oracle-enhanced"
  gem.authors = ["Raimonds Simanovskis"]
  gem.extra_rdoc_files = ['README.md']
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

RSpec::Core::RakeTask.new(:rcov) do |t|
  t.rcov = true
  t.rcov_opts =  ['--exclude', '/Library,spec/']
end

desc "Clear test database"
task :clear do
  require "./spec/spec_helper"
  ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  require "active_support/core_ext"
  ActiveRecord::Base.connection.execute_structure_dump(ActiveRecord::Base.connection.full_drop)
  ActiveRecord::Base.connection.execute("PURGE RECYCLEBIN") rescue nil
end

# Clear test database before running spec and rcov
task :spec => :clear
task :rcov => :clear

task :default => :spec

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'doc'
  rdoc.title = "activerecord-oracle_enhanced-adapter #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
