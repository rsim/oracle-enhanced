Gem::Specification.new do |s|
  s.name = %q{activerecord-oracle_enhanced-adapter}
  s.version = "1.7.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.required_ruby_version     = '>= 2.2.2'
  s.license = 'MIT'
  s.authors = [%q{Raimonds Simanovskis}]
  s.date = %q{2016-10-14}
  s.description = %q{Oracle "enhanced" ActiveRecord adapter contains useful additional methods for working with new and legacy Oracle databases.
This adapter is superset of original ActiveRecord Oracle adapter.
}
  s.email = %q{raimonds.simanovskis@gmail.com}
  s.extra_rdoc_files = [
    "README.md"
  ]
  s.files = [
    ".rspec",
    "Gemfile",
    "History.md",
    "License.txt",
    "README.md",
    "RUNNING_TESTS.md",
    "Rakefile",
    "VERSION",
    "activerecord-oracle_enhanced-adapter.gemspec",
    "lib/active_record/connection_adapters/emulation/oracle_adapter.rb",
    "lib/active_record/connection_adapters/oracle_enhanced_adapter.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/column.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/column_dumper.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/context_index.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/cpk.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/database_statements.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/database_tasks.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/jdbc_connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/jdbc_quoting.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/oci_connection.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/oci_quoting.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/procedures.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/quoting.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/schema_creation.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/schema_definitions.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/schema_dumper.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/schema_statements.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/schema_statements_ext.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/structure_dump.rb",
    "lib/active_record/connection_adapters/oracle_enhanced/version.rb",
    "lib/active_record/oracle_enhanced/type/boolean.rb",
    "lib/active_record/oracle_enhanced/type/integer.rb",
    "lib/active_record/oracle_enhanced/type/national_character_string.rb",
    "lib/active_record/oracle_enhanced/type/raw.rb",
    "lib/active_record/oracle_enhanced/type/string.rb",
    "lib/active_record/oracle_enhanced/type/text.rb",
    "lib/activerecord-oracle_enhanced-adapter.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_connection_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_context_index_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_cpk_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_database_tasks_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_data_types_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_dbms_output_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_dirty_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_emulate_oracle_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_procedures_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_schema_dump_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_schema_statements_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_structure_dump_spec.rb",
    "spec/spec_helper.rb"
  ]
  s.homepage = %q{http://github.com/rsim/oracle-enhanced}
  s.require_paths = [%q{lib}]
  s.summary = %q{Oracle enhanced adapter for ActiveRecord}
  s.test_files = [
    "spec/active_record/connection_adapters/oracle_enhanced_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_connection_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_context_index_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_cpk_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_database_tasks_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_data_types_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_dbms_output_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_dirty_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_emulate_oracle_adapter_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_procedures_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_schema_dump_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_schema_statements_spec.rb",
    "spec/active_record/connection_adapters/oracle_enhanced_structure_dump_spec.rb",
    "spec/spec_helper.rb"
  ]
  s.add_runtime_dependency(%q<activerecord>, ["~> 5.0.0"])
  s.add_runtime_dependency(%q<arel>, ["~> 7.1.4"])
  s.add_runtime_dependency(%q<ruby-plsql>, [">= 0.5.0"])
  s.license = 'MIT'
end

