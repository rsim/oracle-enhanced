# frozen_string_literal: true

# Benchmark for OracleEnhanced::Connection#describe.
#
# Intent: compare the describe() implementations across
#   - master: UNION ALL over all_tables/all_views/all_synonyms
#   - PR #2521 branch (add-describe-regression-test): single all_objects query
#   - poc-dbms-utility-name-resolve: DBMS_UTILITY.NAME_RESOLVE
#
# The fixture models the production scenario from #2429: ~1000 objects in
# the schema (700 tables, 100 views, 100 private synonyms, 100 public
# synonyms).
#
# Usage (from repo root):
#   bundle exec ruby script/benchmark_describe.rb                 # setup + run + teardown
#   SKIP_SETUP=1 bundle exec ruby script/benchmark_describe.rb    # reuse previous fixtures
#   SKIP_TEARDOWN=1 bundle exec ruby script/benchmark_describe.rb # keep fixtures for next run
#
# Environment variables honored (same defaults as spec_helper.rb):
#   DATABASE_NAME, DATABASE_HOST, DATABASE_PORT, DATABASE_USER,
#   DATABASE_PASSWORD, ITERATIONS, TABLE_COUNT, VIEW_COUNT, SYNONYM_COUNT.

require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "oci8" if RUBY_ENGINE == "ruby"
require "active_record"
require "active_record/connection_adapters/oracle_enhanced_adapter"

TABLE_COUNT   = Integer(ENV["TABLE_COUNT"]   || 700)
VIEW_COUNT    = Integer(ENV["VIEW_COUNT"]    || 100)
SYNONYM_COUNT = Integer(ENV["SYNONYM_COUNT"] || 200) # half private, half public
ITERATIONS    = Integer(ENV["ITERATIONS"]    || 1)
SKIP_SETUP    = ENV["SKIP_SETUP"]    == "1"
SKIP_TEARDOWN = ENV["SKIP_TEARDOWN"] == "1"

ActiveRecord::Base.establish_connection(
  adapter:  "oracle_enhanced",
  database: ENV["DATABASE_NAME"]     || "XEPDB1",
  host:     ENV["DATABASE_HOST"]     || "127.0.0.1",
  port:     Integer(ENV["DATABASE_PORT"] || 1521),
  username: ENV["DATABASE_USER"]     || "oracle_enhanced",
  password: ENV["DATABASE_PASSWORD"] || "oracle_enhanced"
)

conn  = ActiveRecord::Base.connection
raw   = conn.instance_variable_get(:@raw_connection) || conn.raw_connection
owner = (ENV["DATABASE_USER"] || "oracle_enhanced").upcase

def t(label)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  printf("%-20s %8.2fs\n", label, elapsed)
end

def safe_exec(conn, sql)
  conn.execute(sql)
rescue ActiveRecord::StatementInvalid
  # idempotent: ignore "already exists" / "does not exist"
end

table_names   = (1..TABLE_COUNT).map { |i| "bench_tbl_%04d" % i }
view_names    = (1..VIEW_COUNT).map  { |i| "bench_vw_%04d"  % i }
priv_syn_half = SYNONYM_COUNT / 2
pub_syn_half  = SYNONYM_COUNT - priv_syn_half
priv_synonyms = (1..priv_syn_half).map { |i| "bench_syn_%04d" % i }
pub_synonyms  = (1..pub_syn_half).map  { |i| "bench_pub_%04d" % i }

unless SKIP_SETUP
  puts "==> Creating #{TABLE_COUNT} tables, #{VIEW_COUNT} views, " \
       "#{priv_syn_half} private + #{pub_syn_half} public synonyms"
  t("create tables") do
    table_names.each { |n| safe_exec conn, "CREATE TABLE #{n} (id NUMBER)" }
  end
  t("create views") do
    view_names.each_with_index do |vn, i|
      safe_exec conn, "CREATE VIEW #{vn} AS SELECT * FROM #{table_names[i % TABLE_COUNT]}"
    end
  end
  t("create synonyms") do
    priv_synonyms.each_with_index do |sn, i|
      safe_exec conn, "CREATE SYNONYM #{sn} FOR #{table_names[i % TABLE_COUNT]}"
    end
    pub_synonyms.each_with_index do |sn, i|
      safe_exec conn, "CREATE PUBLIC SYNONYM #{sn} FOR #{owner}.#{table_names[i % TABLE_COUNT]}"
    end
  end
end

begin
  all_names = table_names + view_names + priv_synonyms + pub_synonyms

  # Warm-up pass so dictionary-cache / shared-pool state is primed; the
  # first describe() after login otherwise dominates wall clock.
  all_names.first(50).each { |n| raw.send(:describe, n) }

  head_branch = `git rev-parse --abbrev-ref HEAD`.strip
  head_sha    = `git rev-parse --short HEAD`.strip
  puts
  puts "==> branch: #{head_branch} (#{head_sha})"
  puts "==> fixtures: #{TABLE_COUNT} tables, #{VIEW_COUNT} views, " \
       "#{priv_syn_half} private synonyms, #{pub_syn_half} public synonyms"
  puts "==> describe() calls per pass: #{all_names.size}"
  puts "==> passes: #{ITERATIONS}"
  puts

  printf("%-20s %10s %10s\n", "case", "wall(s)", "avg(ms)")
  cases = {
    "tables"          => table_names,
    "views"           => view_names,
    "private synonyms" => priv_synonyms,
    "public synonyms"  => pub_synonyms,
    "all mixed"        => all_names.shuffle,
  }
  cases.each do |label, names|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ITERATIONS.times { names.each { |n| raw.send(:describe, n) } }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    per_call_ms = (elapsed * 1000.0) / (ITERATIONS * names.size)
    printf("%-20s %10.3f %10.3f\n", label, elapsed, per_call_ms)
  end
ensure
  unless SKIP_TEARDOWN
    puts
    puts "==> Dropping fixtures"
    t("drop public syns") { pub_synonyms.each  { |n| safe_exec conn, "DROP PUBLIC SYNONYM #{n}" } }
    t("drop private syns") { priv_synonyms.each { |n| safe_exec conn, "DROP SYNONYM #{n}" } }
    t("drop views")        { view_names.each    { |n| safe_exec conn, "DROP VIEW #{n}" } }
    t("drop tables")       { table_names.each   { |n| safe_exec conn, "DROP TABLE #{n} PURGE" } }
  end
end
