# frozen_string_literal: true

require "rubygems"
require "bundler"
require "bundler/gem_tasks"
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require "rake"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

desc "Clear test database"
task :clear do
  require "./spec/spec_helper"
  ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  require "active_support/core_ext"
  ActiveRecord::Base.connection.execute_structure_dump(ActiveRecord::Base.connection.full_drop)
  ActiveRecord::Base.connection.execute("PURGE RECYCLEBIN") rescue nil
end

# Clear test database before running spec
task spec: :clear

task default: :spec

begin
  require "rdoc/task"
rescue LoadError
  # The Gemfile bundles rdoc only on platforms :ruby; skip the RDoc task without it
else
  Rake::RDocTask.new do |rdoc|
    spec = Bundler::GemHelper.gemspec

    rdoc.rdoc_dir = "doc"
    rdoc.title = "#{spec.name} #{spec.version}"
    rdoc.rdoc_files.include("README*")
    rdoc.rdoc_files.include("lib/**/*.rb")
  end
end
