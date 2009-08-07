require 'rubygems'
gem 'hoe', '>= 2.1.0'
require 'hoe'
require 'fileutils'

Hoe.plugin :newgem
Hoe.plugin :website

# %w[rubygems rake rake/clean fileutils newgem rubigen].each { |f| require f }
require File.dirname(__FILE__) + '/lib/active_record/connection_adapters/oracle_enhanced_version'

# Generate all the Rake tasks
# Run 'rake -T' to see list of generated tasks (from gem root directory)
$hoe = Hoe.spec('activerecord-oracle_enhanced-adapter') do
  self.version            = ActiveRecord::ConnectionAdapters::OracleEnhancedVersion::VERSION
  self.developer('Raimonds Simanovskis', 'raimonds.simanovskis@gmail.com')
  self.changes            = self.paragraphs_of("History.txt", 0..1).join("\n\n")
  self.rubyforge_name     = 'oracle-enhanced'
  self.summary            = "Oracle enhaced adapter for Active Record"
  self.extra_deps         = [
    ['activerecord', '>= 2.0.0']
  ]
  self.extra_rdoc_files     = ['README.rdoc']
  
  self.clean_globs |= %w[**/.DS_Store tmp *.log]
  path = self.rubyforge_name
  self.remote_rdoc_dir = File.join(path.gsub(/^#{self.rubyforge_name}\/?/,''), 'rdoc')
  self.rsync_args = '-av --delete --ignore-errors'
end

require 'newgem/tasks' # load /tasks/*.rake
Dir['tasks/**/*.rake'].each { |t| load t }

# want other tests/tasks run by default? Add them to the list
remove_task :default
task :default => [:spec]
