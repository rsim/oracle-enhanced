# frozen_string_literal: true

describe "OracleEnhancedAdapter date type detection based on column names" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute "DROP TABLE test_employees" rescue nil
    @conn.execute "DROP SEQUENCE test_employees_seq" rescue nil
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        email         VARCHAR2(25),
        phone_number  VARCHAR2(20),
        hire_date     DATE,
        job_id        NUMBER(6,0),
        salary        NUMBER(8,2),
        commission_pct  NUMBER(2,2),
        manager_id    NUMBER(6,0),
        department_id NUMBER(4,0),
        created_at    DATE,
        updated_at    DATE
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  describe "/ DATE values from ActiveRecord model" do
    before(:each) do
      class ::TestEmployee < ActiveRecord::Base
        self.primary_key = "employee_id"
      end
    end

    def create_test_employee(params = {})
      @today = params[:today] || Date.new(2008, 8, 19)
      @now = params[:now] || Time.local(2008, 8, 19, 17, 03, 59)
      @employee = TestEmployee.create(
        first_name: "First",
        last_name: "Last",
        hire_date: @today,
        created_at: @now
      )
      @employee.reload
    end

    after(:each) do
      # @employee.destroy if @employee
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should return Time value from DATE column if emulate_dates_by_column_name is false" do
      class ::TestEmployee < ActiveRecord::Base
        attribute :hire_date, :datetime
      end
      create_test_employee
      expect(@employee.hire_date.class).to eq(Time)
    end

    it "should return Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
      create_test_employee
      expect(@employee.hire_date.class).to eq(Date)
    end

    it "should return Date value from DATE column with old date value if column name contains 'date' and emulate_dates_by_column_name is true" do
      create_test_employee(today: Date.new(1900, 1, 1))
      expect(@employee.hire_date.class).to eq(Date)
    end

    it "should return Time value from DATE column if column name does not contain 'date' and emulate_dates_by_column_name is true" do
      class ::TestEmployee < ActiveRecord::Base
        # set_date_columns :created_at
        attribute :created_at, :datetime
      end
      create_test_employee
      expect(@employee.created_at.class).to eq(Time)
    end

    it "should return Time value from DATE column if emulate_dates_by_column_name is true but column is defined as datetime" do
      class ::TestEmployee < ActiveRecord::Base
        # set_datetime_columns :hire_date
        attribute :hire_date, :datetime
      end
      create_test_employee
      expect(@employee.hire_date.class).to eq(Time)
      # change to current time with hours, minutes and seconds
      @employee.hire_date = @now
      @employee.save!
      @employee.reload
      expect(@employee.hire_date.class).to eq(Time)
      expect(@employee.hire_date).to eq(@now)
    end

    it "should guess Date or Time value if emulate_dates is true" do
      class ::TestEmployee < ActiveRecord::Base
        attribute :hire_date, :date
        attribute :created_at, :datetime
      end
      create_test_employee
      expect(@employee.hire_date.class).to eq(Date)
      expect(@employee.created_at.class).to eq(Time)
    end

  end

end

describe "OracleEnhancedAdapter integer type detection based on column names" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute "DROP TABLE test2_employees" rescue nil
    @conn.execute <<-SQL
      CREATE TABLE test2_employees (
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
        is_manager    NUMBER(1),
        department_id NUMBER(4,0),
        created_at    DATE
      )
    SQL
    @conn.execute "DROP SEQUENCE test2_employees_seq" rescue nil
    @conn.execute <<-SQL
      CREATE SEQUENCE test2_employees_seq  MINVALUE 1
        INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE test2_employees"
    @conn.execute "DROP SEQUENCE test2_employees_seq"
  end

  describe "/ NUMBER values from ActiveRecord model" do
    before(:each) do
      class ::Test2Employee < ActiveRecord::Base
      end
    end

    after(:each) do
      Object.send(:remove_const, "Test2Employee")
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = true
      ActiveRecord::Base.clear_cache!
    end

    def create_employee2
      @employee2 = Test2Employee.create(
        first_name: "First",
        last_name: "Last",
        job_id: 1,
        is_manager: 1,
        salary: 1000
      )
      @employee2.reload
    end

    it "should return BigDecimal value from NUMBER column if emulate_integers_by_column_name is false" do
      create_employee2
      expect(@employee2.job_id.class).to eq(BigDecimal)
    end

    it "should return Integer value from NUMBER column if column name contains 'id' and emulate_integers_by_column_name is true" do
      class ::Test2Employee < ActiveRecord::Base
        attribute :job_id, :integer
      end
      create_employee2
      expect(@employee2.job_id).to be_a(Integer)
    end

    it "should return Integer value from NUMBER column with integer value using _before_type_cast method" do
      create_employee2
      expect(@employee2.job_id_before_type_cast).to be_a(Integer)
    end

    it "should return BigDecimal value from NUMBER column if column name does not contain 'id' and emulate_integers_by_column_name is true" do
      create_employee2
      expect(@employee2.salary.class).to eq(BigDecimal)
    end

    it "should return Integer value from NUMBER column if column specified in set_integer_columns" do
      class ::Test2Employee < ActiveRecord::Base
        attribute :job_id, :integer
      end
      create_employee2
      expect(@employee2.job_id).to be_a(Integer)
    end

    it "should return Boolean value from NUMBER(1) column if emulate booleans is used" do
      create_employee2
      expect(@employee2.is_manager.class).to eq(TrueClass)
    end

    it "should return Integer value from NUMBER(1) column if emulate booleans is not used" do
      class ::Test2Employee < ActiveRecord::Base
        attribute :is_manager, :integer
      end
      create_employee2
      expect(@employee2.is_manager).to be_a(Integer)
    end

    it "should return Integer value from NUMBER(1) column if column specified in set_integer_columns" do
      class ::Test2Employee < ActiveRecord::Base
        attribute :is_manager, :integer
      end
      create_employee2
      expect(@employee2.is_manager).to be_a(Integer)
    end

  end

end

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

    it "should return boolean value from VARCHAR2 boolean column if column specified in set_boolean_columns" do
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

    it "should return string value from VARCHAR2 column with boolean column name but is specified in set_string_columns" do
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

describe "OracleEnhancedAdapter timestamp with timezone support" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.default_timezone = :local
    ActiveRecord::Base.establish_connection(CONNECTION_WITH_TIMEZONE_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string        :first_name,  limit: 20
        t.string        :last_name,  limit: 25
        t.string        :email, limit: 25
        t.string        :phone_number, limit: 20
        t.date          :hire_date
        t.decimal       :job_id, scale: 0, precision: 6
        t.decimal       :salary, scale: 2, precision: 8
        t.decimal       :commission_pct, scale: 2, precision: 2
        t.decimal       :manager_id, scale: 0, precision: 6
        t.decimal       :department_id, scale: 0, precision: 4
        t.timestamp     :created_at
        t.timestamptz   :created_at_tz
        t.timestampltz  :created_at_ltz
      end
    end
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    ActiveRecord::Base.default_timezone = :utc
  end

  describe "/ TIMESTAMP WITH TIME ZONE values from ActiveRecord model" do
    before(:all) do
      class ::TestEmployee < ActiveRecord::Base
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should return Time value from TIMESTAMP columns" do
      @now = Time.local(2008, 5, 26, 23, 11, 11, 0)
      @employee = TestEmployee.create(
        created_at: @now,
        created_at_tz: @now,
        created_at_ltz: @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        expect(@employee.send(c).class).to eq(Time)
        expect(@employee.send(c).to_f).to eq(@now.to_f)
      end
    end

    it "should return Time value with fractional seconds from TIMESTAMP columns" do
      @now = Time.local(2008, 5, 26, 23, 11, 11, 10)
      @employee = TestEmployee.create(
        created_at: @now,
        created_at_tz: @now,
        created_at_ltz: @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        expect(@employee.send(c).class).to eq(Time)
        expect(@employee.send(c).to_f).to eq(@now.to_f)
      end
    end

  end

end

describe "OracleEnhancedAdapter assign string to :date and :datetime columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string    :first_name,  limit: 20
        t.string    :last_name,  limit: 25
        t.date      :hire_date
        t.date      :last_login_at
        t.datetime  :last_login_at_ts
      end
    end
    class ::TestEmployee < ActiveRecord::Base
      attribute :last_login_at, :datetime
    end
    @today = Date.new(2008, 6, 28)
    @today_iso = "2008-06-28"
    @today_nls = "28.06.2008"
    @nls_date_format = "%d.%m.%Y"
    @now = Time.local(2008, 6, 28, 13, 34, 33)
    @now_iso = "2008-06-28 13:34:33"
    @now_nls = "28.06.2008 13:34:33"
    @nls_time_format = "%d.%m.%Y %H:%M:%S"
    @now_nls_with_tz = "28.06.2008 13:34:33+05:00"
    @nls_with_tz_time_format = "%d.%m.%Y %H:%M:%S%Z"
    @now_with_tz = Time.parse @now_nls_with_tz
  end

  after(:all) do
    Object.send(:remove_const, "TestEmployee")
    @conn.drop_table :test_employees, if_exists: true
    ActiveRecord::Base.clear_cache!
  end

  after(:each) do
    ActiveRecord::Base.default_timezone = :utc
  end

  it "should assign ISO string to date column" do
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      hire_date: @today_iso
    )
    expect(@employee.hire_date).to eq(@today)
    @employee.reload
    expect(@employee.hire_date).to eq(@today)
  end

  it "should assign NLS string to date column" do
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      hire_date: @today_nls
    )
    expect(@employee.hire_date).to eq(@today)
    @employee.reload
    expect(@employee.hire_date).to eq(@today)
  end

  it "should assign ISO time string to date column" do
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      hire_date: @now_iso
    )
    expect(@employee.hire_date).to eq(@today)
    @employee.reload
    expect(@employee.hire_date).to eq(@today)
  end

  it "should assign NLS time string to date column" do
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      hire_date: @now_nls
    )
    expect(@employee.hire_date).to eq(@today)
    @employee.reload
    expect(@employee.hire_date).to eq(@today)
  end

  it "should assign ISO time string to datetime column" do
    ActiveRecord::Base.default_timezone = :local
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      last_login_at: @now_iso
    )
    expect(@employee.last_login_at).to eq(@now)
    @employee.reload
    expect(@employee.last_login_at).to eq(@now)
  end

  it "should assign NLS time string to datetime column" do
    ActiveRecord::Base.default_timezone = :local
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      last_login_at: @now_nls
    )
    expect(@employee.last_login_at).to eq(@now)
    @employee.reload
    expect(@employee.last_login_at).to eq(@now)
  end

  it "should assign NLS time string with time zone to datetime column" do
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      last_login_at: @now_nls_with_tz
    )
    expect(@employee.last_login_at).to eq(@now_with_tz)
    @employee.reload
    expect(@employee.last_login_at).to eq(@now_with_tz)
  end

  it "should assign ISO date string to datetime column" do
    ActiveRecord::Base.default_timezone = :local
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      last_login_at: @today_iso
    )
    expect(@employee.last_login_at).to eq(@today.to_time)
    @employee.reload
    expect(@employee.last_login_at).to eq(@today.to_time)
  end

  it "should assign NLS date string to datetime column" do
    ActiveRecord::Base.default_timezone = :local
    @employee = TestEmployee.create(
      first_name: "First",
      last_name: "Last",
      last_login_at: @today_nls
    )
    expect(@employee.last_login_at).to eq(@today.to_time)
    @employee.reload
    expect(@employee.last_login_at).to eq(@today.to_time)
  end

end

describe "OracleEnhancedAdapter handling of CLOB columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.text    :comments
      end
      create_table :test2_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.text    :comments
      end
      create_table :test_serialize_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
      end
      add_column :test_serialize_employees, :comments, :text
    end

    @char_data = (0..127).to_a.pack("C*") * 800
    @char_data2 = ((1..127).to_a.pack("C*") + "\0") * 800

    class ::TestEmployee < ActiveRecord::Base; end
    class ::Test2Employee < ActiveRecord::Base
      serialize :comments
    end
    class ::TestEmployeeReadOnlyClob < ActiveRecord::Base
      self.table_name = "test_employees"
      attr_readonly :comments
    end
    class ::TestSerializeEmployee < ActiveRecord::Base
      serialize :comments
      attr_readonly :comments
    end
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    @conn.drop_table :test2_employees, if_exists: true
    @conn.drop_table :test_serialize_employees, if_exists: true
    Object.send(:remove_const, "TestEmployee")
    Object.send(:remove_const, "Test2Employee")
    Object.send(:remove_const, "TestEmployeeReadOnlyClob")
    Object.send(:remove_const, "TestSerializeEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should create record without CLOB data when attribute is serialized" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last"
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should accept Symbol value for CLOB column" do
    @employee = TestEmployee.create!(
      comments: :test_comment
    )
    expect(@employee).to be_valid
  end

  it "should respect attr_readonly setting for CLOB column" do
    @employee = TestEmployeeReadOnlyClob.create!(
      first_name: "First",
      comments: "initial"
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to eq("initial")
    @employee.comments = "changed"
    expect(@employee.save).to eq(true)
    @employee.reload
    expect(@employee.comments).to eq("initial")
  end

  it "should work for serialized readonly CLOB columns", serialized: true do
    @employee = TestSerializeEmployee.new(
      first_name: "First",
      comments: nil
    )
    expect(@employee.comments).to be_nil
    expect(@employee.save).to eq(true)
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = {}
    expect(@employee.save).to eq(true)
    @employee.reload
    #should not set readonly
    expect(@employee.comments).to be_nil
  end

  it "should create record with CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @char_data
    )
    @employee.reload
    expect(@employee.comments).to eq(@char_data)
  end

  it "should update record with CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = @char_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@char_data)
  end

  it "should update record with zero-length CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has existing CLOB data with different CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @char_data
    )
    @employee.reload
    @employee.comments = @char_data2
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@char_data2)
  end

  it "should update record that has existing CLOB data with nil" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @char_data
    )
    @employee.reload
    @employee.comments = nil
    @employee.save!
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should update record that has existing CLOB data with zero-length CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @char_data
    )
    @employee.reload
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has zero-length CLOB data with non-empty CLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: ""
    )
    @employee.reload
    expect(@employee.comments).to eq("")
    @employee.comments = @char_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@char_data)
  end

  it "should store serializable ruby data structures" do
    ruby_data1 = { "arbitrary1" => ["ruby", :data, 123] }
    ruby_data2 = { "arbitrary2" => ["ruby", :data, 123] }
    @employee = Test2Employee.create!(
      comments: ruby_data1
    )
    @employee.reload
    expect(@employee.comments).to eq(ruby_data1)
    @employee.comments = ruby_data2
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(ruby_data2)
  end

  it "should keep unchanged serialized data when other columns changed" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last",
      comments: "initial serialized data"
    )
    @employee.first_name = "Steve"
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq("initial serialized data")
  end

  it "should keep serialized data after save" do
    @employee = Test2Employee.new
    @employee.comments = { length: { is: 1 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 1 })
    @employee.comments = { length: { is: 2 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 2 })
  end
end

describe "OracleEnhancedAdapter handling of NCLOB columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.column  :comments, :ntext
      end
      create_table :test2_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.column  :comments, :ntext
      end
      create_table :test_serialize_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
      end
      add_column :test_serialize_employees, :comments, :ntext
    end

    @nchar_data = '日オメヌ'
    @nchar_data2 = '使セ転'

    class ::TestEmployee < ActiveRecord::Base; end
    class ::Test2Employee < ActiveRecord::Base
      serialize :comments
    end
    class ::TestEmployeeReadOnlyNClob < ActiveRecord::Base
      self.table_name = "test_employees"
      attr_readonly :comments
    end
    class ::TestSerializeEmployee < ActiveRecord::Base
      serialize :comments
      attr_readonly :comments
    end
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    @conn.drop_table :test2_employees, if_exists: true
    @conn.drop_table :test_serialize_employees, if_exists: true
    Object.send(:remove_const, "TestEmployee")
    Object.send(:remove_const, "Test2Employee")
    Object.send(:remove_const, "TestEmployeeReadOnlyNClob")
    Object.send(:remove_const, "TestSerializeEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should create record without NCLOB data when attribute is serialized" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last"
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should accept Symbol value for NCLOB column" do
    @employee = TestEmployee.create!(
      comments: :test_comment
    )
    expect(@employee).to be_valid
  end

  it "should respect attr_readonly setting for NCLOB column" do
    @employee = TestEmployeeReadOnlyNClob.create!(
      first_name: "First",
      comments: '日オメヌロ'
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to eq('日オメヌロ')
    @employee.comments = "勢はう"
    expect(@employee.save).to eq(true)
    @employee.reload
    expect(@employee.comments).to eq('日オメヌロ')
  end

  it "should work for serialized readonly NCLOB columns", serialized: true do
    @employee = TestSerializeEmployee.new(
      first_name: "First",
      comments: nil
    )
    expect(@employee.comments).to be_nil
    expect(@employee.save).to eq(true)
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = {}
    expect(@employee.save).to eq(true)
    @employee.reload
    #should not set readonly
    expect(@employee.comments).to be_nil
  end

  it "should create record with NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nchar_data
    )
    @employee.reload
    expect(@employee.comments).to eq(@nchar_data)
  end

  it "should update record with NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = @nchar_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nchar_data)
  end

  it "should update record with zero-length NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has existing NCLOB data with different NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nchar_data
    )
    @employee.reload
    @employee.comments = @nchar_data2
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nchar_data2)
  end

  it "should update record that has existing NCLOB data with nil" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nchar_data
    )
    @employee.reload
    @employee.comments = nil
    @employee.save!
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should update record that has existing NCLOB data with zero-length NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nchar_data
    )
    @employee.reload
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has zero-length NCLOB data with non-empty NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: ""
    )
    @employee.reload
    expect(@employee.comments).to eq("")
    @employee.comments = @nchar_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nchar_data)
  end

  it "should store serializable ruby data structures" do
    ruby_data1 = { "arbitrary1" => ["ruby", :data, 123] }
    ruby_data2 = { "arbitrary2" => ["ruby", :data, 123] }
    @employee = Test2Employee.create!(
      comments: ruby_data1
    )
    @employee.reload
    expect(@employee.comments).to eq(ruby_data1)
    @employee.comments = ruby_data2
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(ruby_data2)
  end

  it "should keep unchanged serialized data when other columns changed" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last",
      comments: "福れは"
    )
    @employee.first_name = "Steve"
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq("福れは")
  end

  it "should keep serialized data after save" do
    @employee = Test2Employee.new
    @employee.comments = { length: { is: 1 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 1 })
    @employee.comments = { length: { is: 2 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 2 })
  end
end

describe "OracleEnhancedAdapter handling of BLOB columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.binary  :binary_data
      end
    end
    class ::TestEmployee < ActiveRecord::Base
    end
    @binary_data = "\0\1\2\3\4\5\6\7\8\9" * 10000
    @binary_data2 = "\1\2\3\4\5\6\7\8\9\0" * 10000
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    Object.send(:remove_const, "TestEmployee")
  end

  after(:each) do
    ActiveRecord::Base.clear_cache!
  end

  it "should create record with BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end

  it "should update record with BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.binary_data).to be_nil
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end

  it "should update record with zero-length BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.binary_data).to be_nil
    @employee.binary_data = ""
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq("")
  end

  it "should update record that has existing BLOB data with different BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = @binary_data2
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data2)
  end

  it "should update record that has existing BLOB data with nil" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = nil
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to be_nil
  end

  it "should update record that has existing BLOB data with zero-length BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = ""
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq("")
  end

  it "should update record that has zero-length BLOB data with non-empty BLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: ""
    )
    @employee.reload
    expect(@employee.binary_data).to eq("")
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end
end

describe "OracleEnhancedAdapter handling of RAW columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string    :first_name,    limit: 20
        t.string    :last_name,     limit: 25
        t.raw       :binary_data,   limit: 1024
      end
    end
    @binary_data = "\0\1\2\3\4\5\6\7\8\9" * 100
    @binary_data2 = "\1\2\3\4\5\6\7\8\9\0" * 100
  end

  after(:all) do
    schema_define do
      drop_table :test_employees
    end
  end

  before(:each) do
    class ::TestEmployee < ActiveRecord::Base
    end
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should create record with RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end

  it "should update record with RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.binary_data).to be_nil
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end

  it "should update record with zero-length RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.binary_data).to be_nil
    @employee.binary_data = ""
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to be_nil
  end

  it "should update record that has existing RAW data with different RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = @binary_data2
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data2)
  end

  it "should update record that has existing RAW data with nil" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = nil
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to be_nil
  end

  it "should update record that has existing RAW data with zero-length RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: @binary_data
    )
    @employee.reload
    @employee.binary_data = ""
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to be_nil
  end

  it "should update record that has zero-length BLOB data with non-empty RAW data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      binary_data: ""
    )
    @employee.reload
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    expect(@employee.binary_data).to eq(@binary_data)
  end
end

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

describe "OracleEnhancedAdapter handling of BINARY_FLOAT columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test2_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.string  :email, limit: 25
        t.string  :phone_number, limit: 25
        t.date    :hire_date
        t.integer :job_id
        t.integer :salary
        t.decimal :commission_pct, scale: 2, precision: 2
        t.float   :hourly_rate
        t.integer :manager_id,  limit: 6
        t.integer :is_manager,  limit: 1
        t.decimal :department_id, scale: 0, precision: 4
        t.timestamps
      end
    end
    class ::Test2Employee < ActiveRecord::Base
    end
  end

  after(:all) do
    Object.send(:remove_const, "Test2Employee")
    @conn.drop_table :test2_employees, if_exists:  true
  end

  it "should set BINARY_FLOAT column type as float" do
    columns = @conn.columns("test2_employees")
    column = columns.detect { |c| c.name == "hourly_rate" }
    expect(column.type).to eq(:float)
  end

  it "should BINARY_FLOAT column type returns an approximate value" do
    employee = Test2Employee.create(hourly_rate: 4.4)

    employee.reload

    expect(employee.hourly_rate).to eq(4.400000095367432)
  end
end

describe "OracleEnhancedAdapter attribute API support for JSON type" do

  include SchemaSpecHelper

  before(:all) do
    @conn = ActiveRecord::Base.connection
    @oracle12c_or_higher = !! @conn.select_value(
      "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 12")
    skip "Not supported in this database version" unless @oracle12c_or_higher
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_posts, force: true do |t|
        t.string  :title
        t.text    :article
      end
      execute "alter table test_posts add constraint test_posts_title_is_json check (title is json)"
      execute "alter table test_posts add constraint test_posts_article_is_json check (article is json)"
    end

    class ::TestPost < ActiveRecord::Base
      attribute :title, :json
      attribute :article, :json
    end
  end

  after(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      drop_table :test_posts, if_exists: true
    end
  end

  before(:each) do
    TestPost.delete_all
  end

  it "should support attribute api for JSON" do
    post = TestPost.create!(title: { "publish" => true, "foo" => "bar" }, article: { "bar" => "baz" })
    post.reload
    expect(post.title).to eq ({ "publish" => true, "foo" => "bar" })
    expect(post.article).to eq ({ "bar" => "baz" })
    post.title = ({ "publish" => false, "foo" => "bar2" })
    post.save
    expect(post.reload.title).to eq ({ "publish" => false, "foo" => "bar2" })
  end

  it "should support IS JSON" do
    TestPost.create!(title: { "publish" => true, "foo" => "bar" })
    count_json = TestPost.where("title is json")
    expect(count_json.size).to eq 1
    count_non_json = TestPost.where("title is not json")
    expect(count_non_json.size).to eq 0
  end
end
