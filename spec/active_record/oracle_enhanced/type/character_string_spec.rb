# frozen_string_literal: true

describe "OracleEnhancedAdapter processing CHAR column" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<~SQL
      CREATE TABLE test_items (
        id       NUMBER(6,0) PRIMARY KEY,
        padded   CHAR(10)
      )
    SQL
    @conn.execute "CREATE SEQUENCE test_items_seq"
  end

  after(:all) do
    @conn.execute "DROP TABLE test_items"
    @conn.execute "DROP SEQUENCE test_items_seq"
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
end
