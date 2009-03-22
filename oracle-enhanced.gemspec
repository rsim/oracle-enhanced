# encoding: utf-8

Gem::Specification.new do |s|
  s.name = %q{activerecord-oracle_enhanced-adapter}
  s.version = "1.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Raimonds Simanovskis"]
  s.date = %q{2009-03-22}
  s.description = %q{Oracle enhanced adapter for ActiveRecord}
  s.email = ["raimonds.simanovskis@gmail.com"]
  s.extra_rdoc_files = ["History.txt", "License.txt", "Manifest.txt", "README.txt"]
  s.files = ["History.txt", "License.txt", "Manifest.txt", "README.txt",
    "lib/active_record/connection_adapters/emulation/oracle_adapter.rb",
    "lib/active_record/connection_adapters/oracle_enhanced.rake",
    "lib/active_record/connection_adapters/oracle_enhanced_adapter.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_core_ext.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_cpk.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_dirty.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_jdbc_connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_oci_connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_procedures.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_reserved_words.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_tasks.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_version.rb",
    "oracle-enhanced.gemspec",
    "spec/active_record/connection_adapters/oracle_enhanced_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_connection_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_core_ext_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_cpk_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_data_types_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_dirty_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_emulate_oracle_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_procedures_spec.rb",
    "spec/spec.opts",
    "spec/spec_helper.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://oracle-enhanced.rubyforge.org}
  s.post_install_message = %q{}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{oracle-enhanced}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Oracle enhanced adapter for ActiveRecord}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<hoe>, [">= 1.8.0"])
    else
      s.add_dependency(%q<hoe>, [">= 1.8.0"])
    end
  else
    s.add_dependency(%q<hoe>, [">= 1.8.0"])
  end
end
