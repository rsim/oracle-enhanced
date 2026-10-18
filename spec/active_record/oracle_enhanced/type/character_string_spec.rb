# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter processing CHAR column" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    @conn.execute <<~SQL
      CREATE TABLE test_items (
        id       NUMBER(6,0) PRIMARY KEY,
        padded   CHAR(10)
      )
    SQL
    @conn.execute "CREATE SEQUENCE test_items_seq"
    # national_character_string_spec also creates a test_items table, with other
    # columns, so do not share statements cached for either table.
    @conn.clear_cache!
  end

  after(:all) do
    @conn.execute "DROP TABLE test_items"
    @conn.execute "DROP SEQUENCE test_items_seq"
    @conn.clear_cache!
  end

  before(:each) do
    class ::TestItem < ActiveRecord::Base
    end
  end

  after(:each) do
    TestItem.delete_all
    Object.send(:remove_const, "TestItem")
    ActiveRecord::Base.clear_cache!
  end

  it "should create and find record" do
    str = "ABC"
    TestItem.create!
    item = TestItem.first
    item.padded = str
    item.save

    expect(TestItem.where(padded: item.padded).count).to eq(1)

    item_reloaded = TestItem.first
    expect(item_reloaded.padded).to eq(str)
  end

  it "should return nil for a NULL CHAR value" do
    TestItem.create!(padded: nil)

    expect(TestItem.first.padded).to be_nil
    expect(@conn.select_value("SELECT padded FROM test_items")).to be_nil
  end

  it "should support case sensitive matching" do
    TestItem.create!(
      padded: "First",
    )
    TestItem.create!(
      padded: "first",
    )

    expect(TestItem.where(TestItem.arel_table[:padded].matches("first%", "\\", true))).to have_attributes(count: 1)
  end

  it "should support case insensitive matching" do
    TestItem.create!(
      padded: "First",
    )
    TestItem.create!(
      padded: "first",
    )

    expect(TestItem.where(TestItem.arel_table[:padded].matches("first%", "\\", false))).to have_attributes(count: 2)
    expect(TestItem.where(TestItem.arel_table[:padded].matches("first%"))).to have_attributes(count: 2)
  end

  it "should support enum predicates" do
    TestItem.enum :padded, { active: "0", archived: "1" }
    item = TestItem.create!(padded: :archived)

    expect(item).to be_archived
    expect(item).not_to be_active
    expect(TestItem.first).to be_archived
    expect(TestItem.archived.count).to eq(1)
  end

  it "should save CHAR value changed in place after save" do
    item = TestItem.create!(padded: "ABC")
    item.padded << "X"

    expect(item).to be_changed
    item.save!
    expect(item.reload.padded).to eq("ABCX")
  end

  it "should not mark CHAR value as changed after save" do
    item = TestItem.create!(padded: "ABC")

    expect(item.padded).to eq("ABC")
    expect(item).not_to be_changed
  end

  it "should hit the query cache for the same CHAR value" do
    TestItem.create!(padded: "ABC")

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      TestItem.cache do
        2.times { TestItem.where(padded: "ABC").to_a }
      end
    end

    expect(queries.size).to eq(1)
  end
end
