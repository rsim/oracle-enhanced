# frozen_string_literal: true

describe "OracleEnhancedAdapter quoting of NCHAR and NVARCHAR2 columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_items (
        id                  NUMBER(6,0) PRIMARY KEY,
        nchar_column        NCHAR(20),
        nvarchar2_column    NVARCHAR2(20),
        char_column         CHAR(20),
        varchar2_column     VARCHAR2(20)
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

  it "should quote with N prefix" do
    columns = @conn.columns("test_items")
    %w(nchar_column nvarchar2_column char_column varchar2_column).each do |col|
      column = columns.detect { |c| c.name == col }
      value = @conn.type_cast_from_column(column, "abc")
      expect(@conn.quote(value)).to eq(column.sql_type[0, 1] == "N" ? "N'abc'" : "'abc'")
      nilvalue = @conn.type_cast_from_column(column, nil)
      expect(@conn.quote(nilvalue)).to eq("NULL")
    end
  end

  it "should create record" do
    nchar_data = "āčē"
    item = TestItem.create(
      nchar_column: nchar_data,
      nvarchar2_column: nchar_data
    ).reload
    expect(item.nchar_column).to eq(nchar_data + " " * 17)
    expect(item.nvarchar2_column).to eq(nchar_data)
  end

end
