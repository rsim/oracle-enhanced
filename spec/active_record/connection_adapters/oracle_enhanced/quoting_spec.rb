# frozen_string_literal: true

describe "OracleEnhancedAdapter quoting" do
  include LoggerSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  describe "reserved words column quoting" do

    before(:all) do
      schema_define do
        create_table :test_reserved_words do |t|
          t.string      :varchar2
          t.integer     :integer
          t.text        :comment
        end
      end
      class ::TestReservedWord < ActiveRecord::Base; end
    end

    after(:all) do
      schema_define do
        drop_table :test_reserved_words
      end
      Object.send(:remove_const, "TestReservedWord")
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "should create table" do
      [:varchar2, :integer, :comment].each do |attr|
        expect(TestReservedWord.columns_hash[attr.to_s].name).to eq(attr.to_s)
      end
    end

    it "should create record" do
      attrs = {
        varchar2: "dummy",
        integer: 1,
        comment: "dummy"
      }
      record = TestReservedWord.create!(attrs)
      record.reload
      attrs.each do |k, v|
        expect(record.send(k)).to eq(v)
      end
    end

    it "should remove double quotes in column quoting" do
      expect(ActiveRecord::Base.connection.quote_column_name('aaa "bbb" ccc')).to eq('"aaa bbb ccc"')
    end

  end

  describe "valid table names" do
    before(:all) do
      @adapter = ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting
    end

    it "should be valid with letters and digits" do
      expect(@adapter.valid_table_name?("abc_123")).to be_truthy
    end

    it "should be valid with schema name" do
      expect(@adapter.valid_table_name?("abc_123.def_456")).to be_truthy
    end

    it "should be valid with schema name and object name in different case" do
      expect(@adapter.valid_table_name?("TEST_DBA.def_456")).to be_truthy
    end

    it "should be valid with $ in name" do
      expect(@adapter.valid_table_name?("sys.v$session")).to be_truthy
    end

    it "should be valid with upcase schema name" do
      expect(@adapter.valid_table_name?("ABC_123.DEF_456")).to be_truthy
    end

    it "should be valid with irregular schema name and database links" do
      expect(@adapter.valid_table_name?('abc$#_123.abc$#_123@abc$#@._123')).to be_truthy
    end

    it "should not be valid with two dots in name" do
      expect(@adapter.valid_table_name?("abc_123.def_456.ghi_789")).to be_falsey
    end

    it "should not be valid with invalid characters" do
      expect(@adapter.valid_table_name?("warehouse-things")).to be_falsey
    end

    it "should not be valid with for camel-case" do
      expect(@adapter.valid_table_name?("Abc")).to be_falsey
      expect(@adapter.valid_table_name?("aBc")).to be_falsey
      expect(@adapter.valid_table_name?("abC")).to be_falsey
    end

    it "should not be valid for names > 30 characters" do
      expect(@adapter.valid_table_name?("a" * 31)).to be_falsey
    end

    it "should not be valid for schema names > 30 characters" do
      expect(@adapter.valid_table_name?(("a" * 31) + ".validname")).to be_falsey
    end

    it "should not be valid for database links > 128 characters" do
      expect(@adapter.valid_table_name?("name@" + "a" * 129)).to be_falsey
    end

    it "should not be valid for names that do not begin with alphabetic characters" do
      expect(@adapter.valid_table_name?("1abc")).to be_falsey
      expect(@adapter.valid_table_name?("_abc")).to be_falsey
      expect(@adapter.valid_table_name?("abc.1xyz")).to be_falsey
      expect(@adapter.valid_table_name?("abc._xyz")).to be_falsey
    end
  end

  describe "table quoting" do

    def create_warehouse_things_table
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table "warehouse-things" do |t|
            t.string      :name
            t.integer     :foo
          end
        end
      end
    end

    def create_camel_case_table
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table "CamelCase" do |t|
            t.string      :name
            t.integer     :foo
          end
        end
      end
    end

    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    after(:each) do
      ActiveRecord::Schema.define do
        suppress_messages do
          drop_table "warehouse-things", if_exists: true
          drop_table "CamelCase", if_exists: true
        end
      end
      Object.send(:remove_const, "WarehouseThing") rescue nil
      Object.send(:remove_const, "CamelCase") rescue nil
    end

    it "should allow creation of a table with non alphanumeric characters" do
      create_warehouse_things_table
      class ::WarehouseThing < ActiveRecord::Base
        self.table_name = "warehouse-things"
      end

      wh = WarehouseThing.create!(name: "Foo", foo: 2)
      expect(wh.id).not_to be_nil

      expect(@conn.tables).to include("warehouse-things")
    end

    it "should allow creation of a table with CamelCase name" do
      create_camel_case_table
      class ::CamelCase < ActiveRecord::Base
        self.table_name = "CamelCase"
      end

      cc = CamelCase.create!(name: "Foo", foo: 2)
      expect(cc.id).not_to be_nil

      expect(@conn.tables).to include("CamelCase")
    end

    it "properly quotes database links" do
      expect(@conn.quote_table_name("asdf@some.link")).to eq('"ASDF"@"SOME.LINK"')
    end
  end
end
