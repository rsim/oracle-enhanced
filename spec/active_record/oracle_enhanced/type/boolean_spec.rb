# frozen_string_literal: true

describe "OracleEnhancedAdapter boolean type detection based on string column types and names" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test3_employees (
        id            NUMBER PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        email         VARCHAR2(25),
        phone_number  VARCHAR2(20),
        hire_date     DATE,
        job_id        NUMBER,
        salary        NUMBER,
        commission_pct  NUMBER(2,2),
        manager_id    NUMBER(6),
        department_id NUMBER(4,0),
        created_at    DATE,
        has_email     CHAR(1),
        has_phone     VARCHAR2(1) DEFAULT 'Y',
        active_flag   VARCHAR2(2),
        manager_yn    VARCHAR2(3) DEFAULT 'N',
        test_boolean  VARCHAR2(3)
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test3_employees_seq  MINVALUE 1
        INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE test3_employees"
    @conn.execute "DROP SEQUENCE test3_employees_seq"
  end

  before(:each) do
    class ::Test3Employee < ActiveRecord::Base
    end
  end

  after(:each) do
    Object.send(:remove_const, "Test3Employee")
    ActiveRecord::Base.clear_cache!
  end

  describe "default values in new records" do
    context "when emulate_booleans_from_strings is false" do
      before do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
      end

      it "are Y or N" do
        subject = Test3Employee.new
        expect(subject.has_phone).to eq("Y")
        expect(subject.manager_yn).to eq("N")
      end
    end

    context "when emulate_booleans_from_strings is true" do
      before do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      end

      it "are True or False" do
        class ::Test3Employee < ActiveRecord::Base
          attribute :has_phone, :boolean
          attribute :manager_yn, :boolean, default: false
        end
        subject = Test3Employee.new
        expect(subject.has_phone).to be_a(TrueClass)
        expect(subject.manager_yn).to be_a(FalseClass)
      end
    end
  end

  it "should translate boolean type to NUMBER(1) if emulate_booleans_from_strings is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    sql_type = ActiveRecord::Base.connection.type_to_sql(:boolean)
    expect(sql_type).to eq("NUMBER(1)")
  end

  describe "/ VARCHAR2 boolean values from ActiveRecord model" do
    before(:each) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    end

    after(:each) do
      ActiveRecord::Base.clear_cache!
    end

    def create_employee3(params = {})
      @employee3 = Test3Employee.create(
        {
        first_name: "First",
        last_name: "Last",
        has_email: true,
        has_phone: false,
        active_flag: true,
        manager_yn: false
        }.merge(params)
      )
      @employee3.reload
    end

    it "should return String value from VARCHAR2 boolean column if emulate_booleans_from_strings is false" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
      create_employee3
      %w(has_email has_phone active_flag manager_yn).each do |col|
        expect(@employee3.send(col.to_sym).class).to eq(String)
      end
    end

    it "should return boolean value from VARCHAR2 boolean column if emulate_booleans_from_strings is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      class ::Test3Employee < ActiveRecord::Base
        attribute :has_email, :boolean
        attribute :active_flag, :boolean
        attribute :has_phone, :boolean, default: false
        attribute :manager_yn, :boolean, default: false
      end
      create_employee3
      %w(has_email active_flag).each do |col|
        expect(@employee3.send(col.to_sym).class).to eq(TrueClass)
        expect(@employee3.send((col + "_before_type_cast").to_sym)).to eq("Y")
      end
      %w(has_phone manager_yn).each do |col|
        expect(@employee3.send(col.to_sym).class).to eq(FalseClass)
        expect(@employee3.send((col + "_before_type_cast").to_sym)).to eq("N")
      end
    end

    it "should return string value from VARCHAR2 column if it is not boolean column and emulate_booleans_from_strings is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      create_employee3
      expect(@employee3.first_name.class).to eq(String)
    end

    it "should return boolean value from VARCHAR2 boolean column if attribute is set to :boolean" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      class ::Test3Employee < ActiveRecord::Base
        attribute :test_boolean, :boolean
      end
      create_employee3(test_boolean: true)
      expect(@employee3.test_boolean.class).to eq(TrueClass)
      expect(@employee3.test_boolean_before_type_cast).to eq("Y")
      create_employee3(test_boolean: false)
      expect(@employee3.test_boolean.class).to eq(FalseClass)
      expect(@employee3.test_boolean_before_type_cast).to eq("N")
      create_employee3(test_boolean: nil)
      expect(@employee3.test_boolean.class).to eq(NilClass)
      expect(@employee3.test_boolean_before_type_cast).to eq(nil)
      create_employee3(test_boolean: "")
      expect(@employee3.test_boolean.class).to eq(NilClass)
      expect(@employee3.test_boolean_before_type_cast).to eq(nil)
    end

    it "should return string value from VARCHAR2 column with boolean column name but attribute is set to :string" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      class ::Test3Employee < ActiveRecord::Base
        attribute :active_flag, :string
      end
      create_employee3
      expect(@employee3.active_flag.class).to eq(String)
    end

  end

end

describe "OracleEnhancedAdapter boolean support when emulate_booleans_from_strings = true" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :posts, force: true do |t|
        t.string  :name,        null: false
        t.boolean :is_default, default: false
      end
    end
  end

  after(:all) do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
  end

  before(:each) do
    class ::Post < ActiveRecord::Base
      attribute :is_default, :boolean
    end
  end

  after(:each) do
    Object.send(:remove_const, "Post")
    ActiveRecord::Base.clear_cache!
  end

  it "boolean should not change after reload" do
    post = Post.create(name: "Test 1", is_default: false)
    expect(post.is_default).to be false
    post.reload
    expect(post.is_default).to be false
  end
end
