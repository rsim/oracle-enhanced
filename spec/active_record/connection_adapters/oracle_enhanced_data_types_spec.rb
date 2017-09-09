# frozen_string_literal: true

describe "OracleEnhancedAdapter date and datetime type detection based on attribute settings" do
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
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should return Date value from DATE column by default" do
      create_test_employee
      expect(@employee.hire_date.class).to eq(Date)
    end

    it "should return Date value from DATE column with old date value by default" do
      create_test_employee(today: Date.new(1900, 1, 1))
      expect(@employee.hire_date.class).to eq(Date)
    end

    it "should return Time value from DATE column if attribute is set to :datetime" do
      class ::TestEmployee < ActiveRecord::Base
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
