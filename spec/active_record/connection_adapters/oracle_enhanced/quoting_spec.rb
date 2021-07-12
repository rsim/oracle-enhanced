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

      @oracle12cr2_or_higher = !!ActiveRecord::Base.connection.select_value(
        "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,4)) >= 12.2")
    end

    it "should be valid with letters and digits" do
      expect(@adapter.valid_table_name?("abc_123", @oracle12cr2_or_higher)).to be_truthy
    end

    it "should be valid with schema name" do
      expect(@adapter.valid_table_name?("abc_123.def_456", @oracle12cr2_or_higher)).to be_truthy
    end

    it "should be valid with schema name and object name in different case" do
      expect(@adapter.valid_table_name?("TEST_DBA.def_456", @oracle12cr2_or_higher)).to be_truthy
    end

    it "should be valid with $ in name" do
      expect(@adapter.valid_table_name?("sys.v$session", @oracle12cr2_or_higher)).to be_truthy
    end

    it "should be valid with upcase schema name" do
      expect(@adapter.valid_table_name?("ABC_123.DEF_456", @oracle12cr2_or_higher)).to be_truthy
    end

    it "should not be valid with two dots in name" do
      expect(@adapter.valid_table_name?("abc_123.def_456.ghi_789", @oracle12cr2_or_higher)).to be_falsey
    end

    it "should not be valid with invalid characters" do
      expect(@adapter.valid_table_name?("warehouse-things", @oracle12cr2_or_higher)).to be_falsey
    end

    it "should not be valid with for camel-case" do
      expect(@adapter.valid_table_name?("Abc", @oracle12cr2_or_higher)).to be_falsey
      expect(@adapter.valid_table_name?("aBc", @oracle12cr2_or_higher)).to be_falsey
      expect(@adapter.valid_table_name?("abC", @oracle12cr2_or_higher)).to be_falsey
    end

    it "should not be valid for names over maximum characters" do
      if @oracle12cr2_or_higher
        expect(@adapter.valid_table_name?("a" * 129, @oracle12cr2_or_higher)).to be_falsey
      else
        expect(@adapter.valid_table_name?("a" * 31, @oracle12cr2_or_higher)).to be_falsey
      end
    end

    it "should not be valid for schema names over maximum characters" do
      if @oracle12cr2_or_higher
        expect(@adapter.valid_table_name?(("a" * 129) + ".validname", @oracle12cr2_or_higher)).to be_falsey
      else
        expect(@adapter.valid_table_name?(("a" * 31) + ".validname", @oracle12cr2_or_higher)).to be_falsey
      end
    end

    it "should not be valid for names that do not begin with alphabetic characters" do
      expect(@adapter.valid_table_name?("1abc", @oracle12cr2_or_higher)).to be_falsey
      expect(@adapter.valid_table_name?("_abc", @oracle12cr2_or_higher)).to be_falsey
      expect(@adapter.valid_table_name?("abc.1xyz", @oracle12cr2_or_higher)).to be_falsey
      expect(@adapter.valid_table_name?("abc._xyz", @oracle12cr2_or_higher)).to be_falsey
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
  end
end
