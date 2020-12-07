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
end
