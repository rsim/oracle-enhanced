# frozen_string_literal: true

version = File.read(File.expand_path("../VERSION", __FILE__)).strip

Gem::Specification.new do |s|
  s.name = "activerecord-oracle_enhanced-adapter"
  s.version = version

  s.required_rubygems_version = ">= 1.8.11"
  s.required_ruby_version     = ">= 2.7.0"
  s.license = "MIT"
  s.authors = ["Raimonds Simanovskis"]
  s.description = 'Oracle "enhanced" ActiveRecord adapter contains useful additional methods for working with new and legacy Oracle databases.
This adapter is superset of original ActiveRecord Oracle adapter.
'
  s.email = "raimonds.simanovskis@gmail.com"
  s.extra_rdoc_files = [
    "README.md"
  ]
  s.files = Dir["History.md", "License.txt", "README.md", "VERSION", "lib/**/*"]
  s.homepage = "http://github.com/rsim/oracle-enhanced"
  s.require_paths = ["lib"]
  s.summary = "Oracle enhanced adapter for ActiveRecord"
  s.test_files = Dir["spec/**/*"]
  s.metadata = {
    "rubygems_mfa_required" => "true"
  }

  s.add_runtime_dependency("activerecord", ["~> 7.2.0"])
  s.add_runtime_dependency("ruby-plsql", [">= 0.6.0"])
  if /java/.match?(RUBY_PLATFORM)
    s.platform = Gem::Platform.new("java")
  else
    s.add_runtime_dependency("ruby-oci8")
  end
end
