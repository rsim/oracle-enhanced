# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "activerecord-oracle_enhanced-adapter"
  s.version     = File.read(File.dirname(__FILE__) + '/VERSION').chomp
  s.authors     = ["Raimonds Simanovskis"]
  s.email       = "raimonds.simanovskis@gmail.com"
  s.homepage    = "http://github.com/rsim/oracle-enhanced"
  s.summary     = "Oracle enhanced adapter for ActiveRecord"
  s.description = %q{Oracle "enhanced" ActiveRecord adapter contains useful additional methods for working with new and legacy Oracle databases. This adapter is superset of original ActiveRecord Oracle adapter.}

  s.files            = Dir.glob("lib/**/*") + %w(VERSION README.md License.txt History.md)
  s.test_files       = Dir.glob("spec/**/*")
  s.require_paths    = ["lib"]
  s.extra_rdoc_files = %w(README.md)

  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 2.10"
  s.add_development_dependency "rdoc", "~> 3.4"
  s.add_development_dependency "ruby-plsql", ">= 0.5.0"
  s.add_development_dependency "actionpack"
  s.add_development_dependency "railties"

  s.add_runtime_dependency "activerecord", "~> 4.0.0.beta"
end
