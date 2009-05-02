%w[rubygems rake rake/clean fileutils newgem rubigen].each { |f| require f }
require File.dirname(__FILE__) + '/lib/active_record/connection_adapters/oracle_enhanced_version'

# Generate all the Rake tasks
# Run 'rake -T' to see list of generated tasks (from gem root directory)
$hoe = Hoe.new('activerecord-oracle_enhanced-adapter', ActiveRecord::ConnectionAdapters::OracleEnhancedVersion::VERSION) do |p|
  p.developer('Raimonds Simanovskis', 'raimonds.simanovskis@gmail.com')
  p.changes              = p.paragraphs_of("History.txt", 0..1).join("\n\n")
  p.rubyforge_name       = 'oracle-enhanced'
  p.summary              = "Oracle enhaced adapter for Active Record"
  p.extra_deps         = [
    ['activerecord', '>= 2.0.0']
  ]
  p.extra_dev_deps = [
    ['newgem', ">= #{::Newgem::VERSION}"]
  ]
  
  p.clean_globs |= %w[**/.DS_Store tmp *.log]
  # path = (p.rubyforge_name == p.name) ? p.rubyforge_name : "\#{p.rubyforge_name}/\#{p.name}"
  path = p.rubyforge_name
  p.remote_rdoc_dir = File.join(path.gsub(/^#{p.rubyforge_name}\/?/,''), 'rdoc')
  p.rsync_args = '-av --delete --ignore-errors'
end

require 'newgem/tasks' # load /tasks/*.rake
Dir['tasks/**/*.rake'].each { |t| load t }

# want other tests/tasks run by default? Add them to the list
remove_task :default
task :default => [:spec]
