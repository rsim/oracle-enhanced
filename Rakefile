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
  gem.add_development_dependency "rspec", ">= 1.3.0"
  gem.extra_rdoc_files = ['README.rdoc']
end
Jeweler::RubygemsDotOrgTasks.new

require 'spec/rake/spectask'
Spec::Rake::SpecTask.new(:spec) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.spec_files = FileList['spec/**/*_spec.rb']
end

Spec::Rake::SpecTask.new(:rcov) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rcov = true
end

task :default => :spec

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'doc'
  rdoc.title = "activerecord-oracle_enhanced-adapter #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
