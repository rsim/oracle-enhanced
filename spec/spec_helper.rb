# frozen_string_literal: true

require "rubygems"
require "bundler"
require "yaml"
Bundler.setup(:default, :development)

$:.unshift(File.expand_path("../../lib", __FILE__))
config_path = File.expand_path("../spec_config.yaml", __FILE__)
if File.exist?(config_path)
  puts "==> Loading config from #{config_path}"
  config = YAML.load_file(config_path)
else
  puts "==> Loading config from ENV or use default"
  config = { "rails" => {}, "database" => {} }
end

require "rspec"

if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby" || RUBY_ENGINE == "truffleruby"
  puts "==> Running specs with ruby version #{RUBY_VERSION}"
  require "oci8"
elsif RUBY_ENGINE == "jruby"
  puts "==> Running specs with JRuby version #{JRUBY_VERSION}"
end

require "active_record"

# Suppress "Created database 'X'" / "Dropped database 'X'" announcements
# from `ActiveRecord::Tasks::DatabaseTasks` during specs that exercise
# the create/drop flows. Allow callers to opt back in by passing
# `VERBOSE=true` on the command line.
ENV["VERBOSE"] ||= "false"

require "active_support/core_ext/module/attribute_accessors"
require "active_support/core_ext/class/attribute_accessors"

require "active_support/log_subscriber"
require "active_record/log_subscriber"

require "logger"

# On JRuby, load the oracle_enhanced adapter first so that the JDBC driver
# (ojdbc17.jar) is registered with DriverManager before ruby-plsql tries to
# load it. ruby-plsql only looks for ojdbc6/7.jar and would fail otherwise.
require "active_record/connection_adapters/oracle_enhanced_adapter"
# ruby-plsql calls ActiveRecord::Base.default_timezone (moved to ActiveRecord
# module in Rails 7.0). Restore the class-level accessor as a shim.
unless ActiveRecord::Base.respond_to?(:default_timezone)
  ActiveRecord::Base.define_singleton_method(:default_timezone) { ActiveRecord.default_timezone }
end
require "ruby-plsql"

puts "==> Effective ActiveRecord version #{ActiveRecord::VERSION::STRING}"

module LoggerSpecHelper
  def set_logger
    @logger = MockLogger.new
    @old_logger = ActiveRecord::Base.logger
    @old_colorize_logging = ActiveSupport.colorize_logging
    ActiveSupport.colorize_logging = false
    ActiveRecord::Base.logger = @logger
  end

  class MockLogger
    LEVELS = %i[debug info warn error fatal unknown].freeze

    attr_reader :flush_count

    def initialize
      @flush_count = 0
      @logged = Hash.new { |h, k| h[k] = [] }
    end

    # used in ActiveRecord 2.x
    def debug?
      true
    end

    def level
      0
    end

    def method_missing(*args)
      if LEVELS.include?(args[0])
        level, message  = args
        @logged[level] << message
      else
        super
      end
    end

    def logged(level)
      @logged[level].compact.map { |l| l.to_s.strip }
    end

    def output(level)
      logged(level).join("\n")
    end

    def flush
      @flush_count += 1
    end

    def clear(level)
      @logged[level] = []
    end
  end

  def clear_logger
    ActiveRecord::Base.logger = @old_logger
    ActiveSupport.colorize_logging = @old_colorize_logging
    @logger = nil
  end
end

# `IGNORE_PAYLOAD_NAMES` was made frozen on Rails main (the constant ships
# as `["SCHEMA", "EXPLAIN"].freeze`), so `replace` raises `FrozenError` on
# recent Rails. Drop "SCHEMA" by reassigning the constant via
# `remove_const` + `const_set` so the override works on both old (mutable)
# and new (frozen) Rails versions. Without "SCHEMA" in the ignore list,
# specs can assert on schema-tagged catalog SQL emitted by the adapter.
%w[ActiveRecord::LogSubscriber ActiveRecord::StructuredEventSubscriber].each do |const_name|
  next unless Object.const_defined?(const_name)
  klass = Object.const_get(const_name)
  next unless klass.const_defined?(:IGNORE_PAYLOAD_NAMES, false)
  klass.send(:remove_const, :IGNORE_PAYLOAD_NAMES)
  klass.const_set(:IGNORE_PAYLOAD_NAMES, ["EXPLAIN"].freeze)
end

module SchemaSpecHelper
  def schema_define(&block)
    # `schema_define` is the primary test-infrastructure helper for setting
    # up tables and indexes inside specs. Silencing deprecation warnings
    # here keeps the CI's "no leaked DEPRECATION" gate (see RSpec.configure
    # below) from catching warnings that come from schema setup itself.
    # Specs that explicitly want to assert on a deprecation should call
    # `ActiveRecord::Schema.define` (or the adapter API) directly instead
    # of going through `schema_define`.
    ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
      ActiveRecord::Schema.define do
        suppress_messages do
          instance_eval(&block)
        end
      end
    end
  end
end

# Wraps a block with the Phase 1 / pre-Phase 2 implicit-constraint
# behavior of `add_index :col, unique: true`. Use this only in specs that
# explicitly exercise the legacy implicit-constraint code path (#2702
# Phase 3 will delete both this helper and the global flag together).
module ImplicitUniqueConstraintHelper
  def with_implicit_unique_constraint_enabled
    adapter = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
    previous = adapter.add_index_unique_creates_constraint
    adapter.add_index_unique_creates_constraint = true
    yield
  ensure
    adapter.add_index_unique_creates_constraint = previous
  end
end

module SchemaDumpingHelper
  def dump_table_schema(table, connection = ActiveRecord::Base.lease_connection)
    old_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
    ActiveRecord::SchemaDumper.ignore_tables = connection.data_sources - [table]
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    stream.string
  ensure
    ActiveRecord::SchemaDumper.ignore_tables = old_ignore_tables
  end
end

RSpec::Matchers.define :be_like do |expected|
  normalize = ->(s) { s.to_s.gsub(/\s+/, " ").strip }
  match { |actual| normalize.call(actual) == normalize.call(expected) }
  failure_message do |actual|
    "expected SQL\n  #{normalize.call(actual).inspect}\nto match\n  #{normalize.call(expected).inspect}"
  end
end

DATABASE_NAME         = config["database"]["name"]         || ENV["DATABASE_NAME"]         || "orcl"
DATABASE_HOST         = config["database"]["host"]         || ENV["DATABASE_HOST"]         || "127.0.0.1"
DATABASE_PORT         = config["database"]["port"]         || ENV["DATABASE_PORT"]         || 1521
DATABASE_USER         = config["database"]["user"]         || ENV["DATABASE_USER"]         || "oracle_enhanced"
DATABASE_PASSWORD     = config["database"]["password"]     || ENV["DATABASE_PASSWORD"]     || "oracle_enhanced"
DATABASE_SCHEMA       = config["database"]["schema"]       || ENV["DATABASE_SCHEMA"]       || "oracle_enhanced_schema"
DATABASE_SYS_PASSWORD = config["database"]["sys_password"] || ENV["DATABASE_SYS_PASSWORD"] || "admin"

connection_params = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_USER,
  password: DATABASE_PASSWORD
}

if ENV["ORACLE_ENHANCED_PREPARED_STATEMENTS_FALSE"]
  connection_params[:prepared_statements] = false
  puts "==> Forcing prepared_statements: false via ORACLE_ENHANCED_PREPARED_STATEMENTS_FALSE"
end

CONNECTION_PARAMS = connection_params.freeze

CONNECTION_WITH_SCHEMA_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_USER,
  password: DATABASE_PASSWORD,
  schema: DATABASE_SCHEMA
}.freeze

CONNECTION_WITH_TIMEZONE_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_USER,
  password: DATABASE_PASSWORD,
  time_zone: "Europe/Riga"
}.freeze

SYS_CONNECTION_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: "sys",
  password: DATABASE_SYS_PASSWORD,
  privilege: "SYSDBA"
}.freeze

SYSTEM_CONNECTION_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: "system",
  password: DATABASE_SYS_PASSWORD
}.freeze

SERVICE_NAME_CONNECTION_PARAMS = {
  adapter: "oracle_enhanced",
  database: "/#{DATABASE_NAME}",
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_USER,
  password: DATABASE_PASSWORD
}.freeze

DATABASE_REMOTE_USER     = config["database"]["remote_user"]     || ENV["DATABASE_REMOTE_USER"]     || "oracle_enhanced_remote"
DATABASE_REMOTE_PASSWORD = config["database"]["remote_password"] || ENV["DATABASE_REMOTE_PASSWORD"] || "oracle_enhanced_remote"

REMOTE_CONNECTION_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_REMOTE_USER,
  password: DATABASE_REMOTE_PASSWORD
}.freeze

DATABASE_NON_DEFAULT_TABLESPACE = config["database"]["non_default_tablespace"] || ENV["DATABASE_NON_DEFAULT_TABLESPACE"] || "SYSTEM"

# set default time zone in TZ environment variable
# which will be used to set session time zone
ENV["TZ"] ||= config["timezone"] || "Europe/Riga"

ActiveRecord::Base.logger = ActiveSupport::Logger.new("debug.log", 0, 100 * 1024 * 1024)

# Spec order is randomized per run so order-dependent issues actually
# surface. The seed is printed at the start of the run (in addition to
# RSpec's normal end-of-run line) so it is visible in partial CI logs
# even when the run hangs or is killed before reaching the end.
#
# To reproduce a specific run locally:
#
#   bundle exec rspec --seed <value>
#
# To narrow down an order-dependent failure to the minimal failing pair:
#
#   bundle exec rspec --seed <value> --bisect
#
RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include ImplicitUniqueConstraintHelper

  # In CI, fail any example that lets a DEPRECATION WARNING leak to
  # stderr — i.e. one that triggered a deprecation but did not consume
  # it via `expect { ... }.to output(/.../).to_stderr` or
  # `OracleEnhanced.deprecator.silence { ... }`. Both of those mechanisms
  # capture/suppress at the inner-most stderr layer, so this outer
  # capture only ever sees stderr that genuinely escaped the example.
  # Skipped outside CI so local runs keep their existing stderr stream.
  if ENV["CI"]
    config.around(:each) do |example|
      outer_stderr = StringIO.new
      original_stderr = $stderr
      $stderr = outer_stderr
      begin
        example.run
      ensure
        $stderr = original_stderr
      end
      if example.exception.nil? && outer_stderr.string.include?("DEPRECATION WARNING")
        raise <<~MSG
          Unexpected DEPRECATION WARNING leaked to stderr from this example. Either
          assert on it with `expect { ... }.to output(/.../).to_stderr` or wrap the
          call in `OracleEnhanced.deprecator.silence { ... }` if the deprecation
          is intentional and not under test. Captured:

          #{outer_stderr.string}
        MSG
      end
    end
  end

  config.before(:suite) do
    seed = RSpec.configuration.seed
    puts "==> Randomized with seed #{seed} (reproduce: bundle exec rspec --seed #{seed})"

    # Oracle moves dropped tables to the recyclebin by default, where they
    # remain (along with their associated identity sequences and PK indexes)
    # under BIN$... names until the bin is purged. Across many test runs the
    # bin accumulates and pollutes inventories like `dba_objects` /
    # `user_objects` even though the tests themselves drop their fixtures.
    # Start each suite from a clean bin so dropped fixtures actually go away.
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.execute("PURGE RECYCLEBIN")
  end
end
