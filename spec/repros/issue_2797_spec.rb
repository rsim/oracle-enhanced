# frozen_string_literal: true
#
# Issue: rsim/oracle-enhanced#2797
# Title: Oracle Enhanced 8.0.0 + Solid Cache on Rails 8.0.4: Rails.cache.fetch raises Arel::BindError
# URL: https://github.com/rsim/oracle-enhanced/issues/2797
# Status: reproduced
# Notes:
#   Reproduced by replaying the exact code path solid_cache 1.0.10's
#   SolidCache::Entry.read_multi uses (see app/models/solid_cache/entry.rb,
#   methods `read_multi` and `select_sql`). That method:
#     1. Builds a placeholder query via
#          `where(key_hash: [1111, 2222]).select(:key, :value).to_sql`
#     2. Does `.gsub("1111, 2222", "?, ?, ?, ?")` to substitute placeholders.
#     3. Calls `connection.select_all(Arel.sql(sql, *binds))`.
#   Oracle Enhanced's Arel visitor `visit_Arel_Nodes_HomogeneousIn`
#   (lib/arel/visitors/oracle_common.rb) emits the inlined list with NO
#   space after the comma -- `IN (1111,2222)` -- so solid_cache's gsub
#   pattern `"1111, 2222"` never matches. The SQL keeps zero placeholders
#   while the caller still passes bind values, and AR raises
#     Arel::BindError: wrong number of bind variables (N for 0)
#   at execution time. This matches the user's report verbatim.
#   Tested against AR 8.2.0.alpha (Rails main) + oracle-enhanced master.
#
#   A plain `Model.where(key_hash: [...]).pluck(...)` does NOT raise --
#   the bug only surfaces when a caller (like Solid Cache) does the
#   placeholder-substitution dance on the to_sql output.

require "spec_helper"

RSpec.describe "Issue #2797: Solid Cache Arel::BindError on IN (...) query" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    schema_define do
      create_table :test_issue_2797_entries, id: false, force: true do |t|
        t.bigint  :key_hash, null: false
        t.string  :key,   limit: 1024, null: false
        t.binary  :value, null: false
        t.timestamp :created_at, null: false
      end
      add_index :test_issue_2797_entries, :key_hash, unique: true,
                name: "ix_test_2797_key_hash"
    end

    class ::TestIssue2797Entry < ActiveRecord::Base
      self.table_name = "test_issue_2797_entries"
      self.primary_key = "key_hash"
    end
  end

  after(:all) do
    Object.send(:remove_const, "TestIssue2797Entry") if defined?(TestIssue2797Entry)
    @conn = ActiveRecord::Base.lease_connection
    @conn.drop_table :test_issue_2797_entries, if_exists: true
    ActiveRecord::Base.clear_cache!
  end

  before(:each) do
    TestIssue2797Entry.delete_all
    TestIssue2797Entry.create!(
      key_hash: 1111,
      key: "test-key-1",
      value: "payload-1",
      created_at: Time.now
    )
  end

  # Reproduces SolidCache::Entry.select_sql verbatim. The template query
  # is rendered via to_sql, then `1111, 2222` is gsubbed to bind
  # placeholders. With Oracle Enhanced the template comes back as
  # `1111,2222` (no space), so the gsub is a no-op and placeholders are
  # never injected.
  def solid_cache_select_sql(key_count)
    TestIssue2797Entry
      .where(key_hash: [1111, 2222])
      .select(:key, :value)
      .to_sql
      .gsub("1111, 2222", Array.new(key_count, "?").join(", "))
  end

  it "documents that oracle-enhanced emits 'IN (1111,2222)' with no space" do
    sql = TestIssue2797Entry
      .where(key_hash: [1111, 2222])
      .select(:key, :value)
      .to_sql

    # This is the root cause: Solid Cache's gsub looks for "1111, 2222"
    # (comma + space), but oracle-enhanced emits no space.
    expect(sql).to include("(1111,2222)")
    expect(sql).not_to include("(1111, 2222)")
  end

  it "raises Arel::BindError on the Solid Cache read_multi code path [BUG]" do
    # This block mirrors SolidCache::Entry.read_multi:
    #   query = Arel.sql(select_sql(keys_batch), *key_hashes_for(keys_batch))
    #   connection.select_all(query, "...")
    key_hashes = [1111]
    sql = solid_cache_select_sql(key_hashes.length)

    # Sanity: the placeholder substitution was a no-op because of the
    # no-space rendering above. So the SQL has 0 placeholders but the
    # caller still passes 1 bind value -- the exact mismatch the issue
    # reports.
    expect(sql.scan("?").length).to eq(0)

    # The BindError raises eagerly inside `Arel.sql` on Rails 8.x+
    # (BoundSqlLiteral validates the placeholder/bind count in its
    # constructor). On older AR versions the same error surfaces at
    # select_all time. Wrap both calls so the assertion holds across
    # versions.
    expect {
      query = Arel.sql(sql, *key_hashes)
      ActiveRecord::Base.lease_connection.select_all(query, "Issue2797 Test Load")
    }.to raise_error(Arel::BindError, /wrong number of bind variables \(1 for 0\)/)
  end
end
