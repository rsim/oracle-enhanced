# encoding: utf-8
require 'spec_helper'

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

  it "should set DATE column type as datetime if emulate_dates_by_column_name is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type.should == :datetime
  end

  it "should set DATE column type as date if column name contains '_date_' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type.should == :date
  end

  it "should set DATE column type as datetime if column name does not contain '_date_' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "created_at"}
    column.type.should == :datetime
  end

  it "should set DATE column type as datetime if column name contains 'date' as part of other word and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "updated_at"}
    column.type.should == :datetime
  end

  it "should return Time value from DATE column if emulate_dates_by_column_name is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type_cast_from_database(Time.now).class.should == Time
  end

  it "should return Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type_cast_from_database(Time.now).class.should == Date
  end

  it "should typecast DateTime value to Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type_cast_from_database(DateTime.new(1900,1,1)).class.should == Date
  end

  describe "/ DATE values from ActiveRecord model" do
    before(:each) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates = false
      class ::TestEmployee < ActiveRecord::Base
        self.primary_key = "employee_id"
      end
    end

    def create_test_employee(params={})
      @today = params[:today] || Date.new(2008,8,19)
      @now = params[:now] || Time.local(2008,8,19,17,03,59)
      @employee = TestEmployee.create(
        :first_name => "First",
        :last_name => "Last",
        :hire_date => @today,
        :created_at => @now
      )
      @employee.reload
    end

    after(:each) do
      # @employee.destroy if @employee
      Object.send(:remove_const, "TestEmployee")
      @conn.clear_types_for_columns
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should return Time value from DATE column if emulate_dates_by_column_name is false" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      create_test_employee
      @employee.hire_date.class.should == Time
    end

    it "should return Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      create_test_employee
      @employee.hire_date.class.should == Date
    end

    it "should return Date value from DATE column with old date value if column name contains 'date' and emulate_dates_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      create_test_employee(:today => Date.new(1900,1,1))
      @employee.hire_date.class.should == Date
    end

    it "should return Time value from DATE column if column name does not contain 'date' and emulate_dates_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      create_test_employee
      @employee.created_at.class.should == Time
    end

    it "should return Date value from DATE column if emulate_dates_by_column_name is false but column is defined as date" do
      class ::TestEmployee < ActiveRecord::Base
        set_date_columns :hire_date
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      create_test_employee
      @employee.hire_date.class.should == Date
    end

    it "should return Date value from DATE column with old date value if emulate_dates_by_column_name is false but column is defined as date" do
      class ::TestEmployee < ActiveRecord::Base
        set_date_columns :hire_date
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      create_test_employee(:today => Date.new(1900,1,1))
      @employee.hire_date.class.should == Date
    end

    it "should see set_date_columns values in different connection" do
      class ::TestEmployee < ActiveRecord::Base
        set_date_columns :hire_date
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      # establish other connection
      other_conn = ActiveRecord::Base.oracle_enhanced_connection(CONNECTION_PARAMS)
      other_conn.get_type_for_column('test_employees', 'hire_date').should == :date
    end

    it "should return Time value from DATE column if emulate_dates_by_column_name is true but column is defined as datetime" do
      class ::TestEmployee < ActiveRecord::Base
        set_datetime_columns :hire_date
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      create_test_employee
      @employee.hire_date.class.should == Time
      # change to current time with hours, minutes and seconds
      @employee.hire_date = @now
      @employee.save!
      @employee.reload
      @employee.hire_date.class.should == Time
      @employee.hire_date.should == @now
    end

    it "should guess Date or Time value if emulate_dates is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates = true
      create_test_employee
      @employee.hire_date.class.should == Date
      @employee.created_at.class.should == Time
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

  it "should set NUMBER column type as decimal if emulate_integers_by_column_name is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = false
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "job_id"}
    column.type.should == :decimal
  end

  it "should set NUMBER column type as integer if emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "job_id"}
    column.type.should == :integer
    column = columns.detect{|c| c.name == "id"}
    column.type.should == :integer
  end

  it "should set NUMBER column type as decimal if column name does not contain 'id' and emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "salary"}
    column.type.should == :decimal
  end

  it "should return BigDecimal value from NUMBER column if emulate_integers_by_column_name is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = false
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "job_id"}
    column.type_cast_from_database(1.0).class.should == BigDecimal
  end

  it "should return Integer value from NUMBER column if column name contains 'id' and emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "job_id"}
    expect(column.type_cast_from_database(1.0)).to be_a(Integer)
  end

  describe "/ NUMBER values from ActiveRecord model" do
    before(:each) do
      class ::Test2Employee < ActiveRecord::Base
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "Test2Employee")
      @conn.clear_types_for_columns
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = true
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    def create_employee2
      @employee2 = Test2Employee.create(
        :first_name => "First",
        :last_name => "Last",
        :job_id => 1,
        :is_manager => 1,
        :salary => 1000
      )
      @employee2.reload
    end

    it "should return BigDecimal value from NUMBER column if emulate_integers_by_column_name is false" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = false
      create_employee2
      @employee2.job_id.class.should == BigDecimal
    end

    it "should return Integer value from NUMBER column if column name contains 'id' and emulate_integers_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      create_employee2
      expect(@employee2.job_id).to be_a(Integer)
    end

    it "should return Integer value from NUMBER column with integer value using _before_type_cast method" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      create_employee2
      expect(@employee2.job_id_before_type_cast).to be_a(Integer)
    end

    it "should return BigDecimal value from NUMBER column if column name does not contain 'id' and emulate_integers_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      create_employee2
      @employee2.salary.class.should == BigDecimal
    end

    it "should return Integer value from NUMBER column if column specified in set_integer_columns" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = false
      Test2Employee.set_integer_columns :job_id
      create_employee2
      expect(@employee2.job_id).to be_a(Integer)
    end

    it "should return Boolean value from NUMBER(1) column if emulate booleans is used" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = true
      create_employee2
      @employee2.is_manager.class.should == TrueClass
    end

    it "should return Integer value from NUMBER(1) column if emulate booleans is not used" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = false
      create_employee2
      expect(@employee2.is_manager).to be_a(Integer)
    end

    it "should return Integer value from NUMBER(1) column if column specified in set_integer_columns" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans = true
      Test2Employee.set_integer_columns :is_manager
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
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
  end

  before(:each) do
    class ::Test3Employee < ActiveRecord::Base
    end
  end

  after(:each) do
    Object.send(:remove_const, "Test3Employee")
    @conn.clear_types_for_columns
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  describe "default values in new records" do
    context "when emulate_booleans_from_strings is false" do
      before do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
      end

      it "are Y or N" do
        subject = Test3Employee.new
        expect(subject.has_phone).to eq('Y')
        expect(subject.manager_yn).to eq('N')
      end
    end

    context "when emulate_booleans_from_strings is true" do
      before do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      end

      it "are True or False" do
        subject = Test3Employee.new
        expect(subject.has_phone).to be_a(TrueClass)
        expect(subject.manager_yn).to be_a(FalseClass)
      end
    end
  end

  it "should set CHAR/VARCHAR2 column type as string if emulate_booleans_from_strings is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    columns = @conn.columns('test3_employees')
    %w(has_email has_phone active_flag manager_yn).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type.should == :string
    end
  end

  it "should set CHAR/VARCHAR2 column type as boolean if emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    columns = @conn.columns('test3_employees')
    %w(has_email has_phone active_flag manager_yn).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type.should == :boolean
    end
  end

  it "should set VARCHAR2 column type as string if column name does not contain 'flag' or 'yn' and emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    columns = @conn.columns('test3_employees')
    %w(phone_number email).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type.should == :string
    end
  end

  it "should return string value from VARCHAR2 boolean column if emulate_booleans_from_strings is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    columns = @conn.columns('test3_employees')
    %w(has_email has_phone active_flag manager_yn).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type_cast_from_database("Y").class.should == String
    end
  end

  it "should return boolean value from VARCHAR2 boolean column if emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    columns = @conn.columns('test3_employees')
    %w(has_email has_phone active_flag manager_yn).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type_cast_from_database("Y").class.should == TrueClass
      column.type_cast_from_database("N").class.should == FalseClass
    end
  end

  it "should translate boolean type to VARCHAR2(1) if emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    ActiveRecord::Base.connection.type_to_sql(
      :boolean, nil, nil, nil).should == "VARCHAR2(1)"
  end

  it "should translate boolean type to NUMBER(1) if emulate_booleans_from_strings is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    ActiveRecord::Base.connection.type_to_sql(
      :boolean, nil, nil, nil).should == "NUMBER(1)"
  end

  it "should get default value from VARCHAR2 boolean column if emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    columns = @conn.columns('test3_employees')
    columns.detect{|c| c.name == 'has_phone'}.default.should eq 'Y'
    columns.detect{|c| c.name == 'manager_yn'}.default.should be false
  end

  describe "/ VARCHAR2 boolean values from ActiveRecord model" do
    before(:each) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
    end

    after(:each) do
      @conn.clear_types_for_columns
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    def create_employee3(params={})
      @employee3 = Test3Employee.create(
        {
        :first_name => "First",
        :last_name => "Last",
        :has_email => true,
        :has_phone => false,
        :active_flag => true,
        :manager_yn => false
        }.merge(params)
      )
      @employee3.reload
    end

    it "should return String value from VARCHAR2 boolean column if emulate_booleans_from_strings is false" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
      create_employee3
      %w(has_email has_phone active_flag manager_yn).each do |col|
        @employee3.send(col.to_sym).class.should == String
      end
    end

    it "should return boolean value from VARCHAR2 boolean column if emulate_booleans_from_strings is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      create_employee3
      %w(has_email active_flag).each do |col|
        @employee3.send(col.to_sym).class.should == TrueClass
        @employee3.send((col+"_before_type_cast").to_sym).should == "Y"
      end
      %w(has_phone manager_yn).each do |col|
        @employee3.send(col.to_sym).class.should == FalseClass
        @employee3.send((col+"_before_type_cast").to_sym).should == "N"
      end
    end

    it "should return string value from VARCHAR2 column if it is not boolean column and emulate_booleans_from_strings is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      create_employee3
      @employee3.first_name.class.should == String
    end

    it "should return boolean value from VARCHAR2 boolean column if column specified in set_boolean_columns" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      Test3Employee.set_boolean_columns :test_boolean
      create_employee3(:test_boolean => true)
      @employee3.test_boolean.class.should == TrueClass
      @employee3.test_boolean_before_type_cast.should == "Y"
      create_employee3(:test_boolean => false)
      @employee3.test_boolean.class.should == FalseClass
      @employee3.test_boolean_before_type_cast.should == "N"
      create_employee3(:test_boolean => nil)
      @employee3.test_boolean.class.should == NilClass
      @employee3.test_boolean_before_type_cast.should == nil
      create_employee3(:test_boolean => "")
      @employee3.test_boolean.class.should == NilClass
      @employee3.test_boolean_before_type_cast.should == nil
    end

    it "should return string value from VARCHAR2 column with boolean column name but is specified in set_string_columns" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
      Test3Employee.set_string_columns :active_flag
      create_employee3
      @employee3.active_flag.class.should == String
    end

  end

end

describe "OracleEnhancedAdapter timestamp with timezone support" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
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
        created_at    TIMESTAMP,
        created_at_tz   TIMESTAMP WITH TIME ZONE,
        created_at_ltz  TIMESTAMP WITH LOCAL TIME ZONE
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  it "should set TIMESTAMP columns type as datetime" do
    columns = @conn.columns('test_employees')
    ts_columns = columns.select{|c| c.name =~ /created_at/}
    ts_columns.each {|c| c.type.should == :timestamp}
  end

  describe "/ TIMESTAMP WITH TIME ZONE values from ActiveRecord model" do
    before(:all) do
      class ::TestEmployee < ActiveRecord::Base
        self.primary_key = "employee_id"
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should cast String to Time for TIMESTAMP columns on assign" do
      @now = Time.local(2008,5,26,23,11,11,0)
      @now_string = @now.to_s
      @employee = TestEmployee.new(
        :created_at => @now_string,
        :created_at_tz => @now_string,
        :created_at_ltz => @now_string
      )
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        @employee.send(c).class.should == Time
        @employee.send(c).to_f.should == @now.to_f
        @employee.send(c).to_s.should == @now_string
      end
    end

    it "should cast String to Time for TIMESTAMP columns on save" do
      @now = Time.local(2008,5,26,23,11,11,0)
      @now_string = @now.to_s
      @employee = TestEmployee.create(
        :created_at => @now_string,
        :created_at_tz => @now_string,
        :created_at_ltz => @now_string
      )
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        @employee.send(c).class.should == Time
        @employee.send(c).to_f.should == @now.to_f
        @employee.send(c).to_s.should == @now_string
      end
    end

    it "should return Time value from TIMESTAMP columns" do
      @now = Time.local(2008,5,26,23,11,11,0)
      @employee = TestEmployee.create(
        :created_at => @now,
        :created_at_tz => @now,
        :created_at_ltz => @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        @employee.send(c).class.should == Time
        @employee.send(c).to_f.should == @now.to_f
      end
    end

    it "should return Time value with fractional seconds from TIMESTAMP columns" do
      @now = Time.local(2008,5,26,23,11,11,10)
      @employee = TestEmployee.create(
        :created_at => @now,
        :created_at_tz => @now,
        :created_at_ltz => @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        @employee.send(c).class.should == Time
        @employee.send(c).to_f.should == @now.to_f
      end
    end

  end

end


describe "OracleEnhancedAdapter date and timestamp with different NLS date formats" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
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
        created_at_ts   TIMESTAMP
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    # @conn.execute %q{alter session set nls_date_format = 'YYYY-MM-DD HH24:MI:SS'}
    @conn.execute %q{alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS'}
    # @conn.execute %q{alter session set nls_timestamp_format = 'YYYY-MM-DD HH24:MI:SS'}
    @conn.execute %q{alter session set nls_timestamp_format = 'DD-MON-YYYY HH24:MI:SS'}
  end

  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  before(:each) do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates = false
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
    class ::TestEmployee < ActiveRecord::Base
      self.primary_key = "employee_id"
    end
    @today = Date.new(2008,6,28)
    @now = Time.local(2008,6,28,13,34,33)
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  def create_test_employee
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today,
      :created_at => @now,
      :created_at_ts => @now
    )
    @employee.reload
  end

  it "should return Time value from DATE column if emulate_dates_by_column_name is false" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
    create_test_employee
    @employee.hire_date.class.should == Time
    @employee.hire_date.should == @today.to_time
  end

  it "should return Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    create_test_employee
    @employee.hire_date.class.should == Date
    @employee.hire_date.should == @today
  end

  it "should return Time value from DATE column if column name does not contain 'date' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    create_test_employee
    @employee.created_at.class.should == Time
    @employee.created_at.should == @now
  end

  it "should return Time value from TIMESTAMP columns" do
    create_test_employee
    @employee.created_at_ts.class.should == Time
    @employee.created_at_ts.should == @now
  end

  it "should quote Date values with TO_DATE" do
    @conn.quote(@today).should == "TO_DATE('#{@today.year}-#{"%02d" % @today.month}-#{"%02d" % @today.day}','YYYY-MM-DD HH24:MI:SS')"
  end

  it "should quote Time values with TO_DATE" do
    @conn.quote(@now).should == "TO_DATE('#{@now.year}-#{"%02d" % @now.month}-#{"%02d" % @now.day} "+
                                "#{"%02d" % @now.hour}:#{"%02d" % @now.min}:#{"%02d" % @now.sec}','YYYY-MM-DD HH24:MI:SS')"
  end

  it "should quote Time values with TO_TIMESTAMP" do
    @ts = @now + 0.1
    @conn.quote(@ts).should == "TO_TIMESTAMP('#{@ts.year}-#{"%02d" % @ts.month}-#{"%02d" % @ts.day} "+
                                "#{"%02d" % @ts.hour}:#{"%02d" % @ts.min}:#{"%02d" % @ts.sec}:100000','YYYY-MM-DD HH24:MI:SS:FF6')"
  end

end

describe "OracleEnhancedAdapter assign string to :date and :datetime columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        hire_date     DATE,
        last_login_at    DATE,
        last_login_at_ts   TIMESTAMP
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    class ::TestEmployee < ActiveRecord::Base
      self.primary_key = "employee_id"
    end
    @today = Date.new(2008,6,28)
    @today_iso = "2008-06-28"
    @today_nls = "28.06.2008"
    @nls_date_format = "%d.%m.%Y"
    @now = Time.local(2008,6,28,13,34,33)
    @now_iso = "2008-06-28 13:34:33"
    @now_nls = "28.06.2008 13:34:33"
    @nls_time_format = "%d.%m.%Y %H:%M:%S"
    @now_nls_with_tz = "28.06.2008 13:34:33+05:00"
    @nls_with_tz_time_format = "%d.%m.%Y %H:%M:%S%Z"
    @now_with_tz = Time.parse @now_nls_with_tz
  end

  after(:all) do
    Object.send(:remove_const, "TestEmployee")
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  before(:each) do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
  end

  it "should assign ISO string to date column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today_iso
    )
    @employee.hire_date.should == @today
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign NLS string to date column" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = @nls_date_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today_nls
    )
    @employee.hire_date.should == @today
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign ISO time string to date column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @now_iso
    )
    @employee.hire_date.should == @today
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign NLS time string to date column" do
    # ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = @nls_date_format
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = @nls_time_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @now_nls
    )
    @employee.hire_date.should == @today
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign ISO time string to datetime column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @now_iso
    )
    @employee.last_login_at.should == @now
    @employee.reload
    @employee.last_login_at.should == @now
  end

  it "should assign NLS time string to datetime column" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = @nls_time_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @now_nls
    )
    @employee.last_login_at.should == @now
    @employee.reload
    @employee.last_login_at.should == @now
  end

  it "should assign NLS time string with time zone to datetime column" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = @nls_with_tz_time_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @now_nls_with_tz
    )
    @employee.last_login_at.should == @now_with_tz
    @employee.reload
    @employee.last_login_at.should == @now_with_tz
  end

  it "should assign ISO date string to datetime column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @today_iso
    )
    @employee.last_login_at.should == @today.to_time
    @employee.reload
    @employee.last_login_at.should == @today.to_time
  end

  it "should assign NLS date string to datetime column" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = @nls_date_format
    # ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = @nls_time_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @today_nls
    )
    @employee.last_login_at.should == @today.to_time
    @employee.reload
    @employee.last_login_at.should == @today.to_time
  end
  
end

describe "OracleEnhancedAdapter handling of CLOB columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        id            NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        comments      CLOB
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    @conn.execute <<-SQL
      CREATE TABLE test2_employees (
        id            NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        comments      CLOB
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test2_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    @conn.execute <<-SQL
      CREATE TABLE test_serialize_employees (
        id            NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25)
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_serialize_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    ActiveRecord::Base.connection.add_column(:test_serialize_employees, :comments, :text)

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
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
    @conn.execute "DROP TABLE test2_employees"
    @conn.execute "DROP SEQUENCE test2_employees_seq"
    @conn.execute "DROP TABLE test_serialize_employees"
    @conn.execute "DROP SEQUENCE test_serialize_employees_seq"
    Object.send(:remove_const, "TestEmployee")
    Object.send(:remove_const, "Test2Employee")
    Object.send(:remove_const, "TestEmployeeReadOnlyClob")
    Object.send(:remove_const, "TestSerializeEmployee")
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  it "should create record without CLOB data when attribute is serialized" do
    @employee = Test2Employee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.should be_valid
    @employee.reload
    @employee.comments.should be_nil
  end

  it "should accept Symbol value for CLOB column" do
    @employee = TestEmployee.create!(
      :comments => :test_comment
    )
    @employee.should be_valid
  end

  it "should respect attr_readonly setting for CLOB column" do
    @employee = TestEmployeeReadOnlyClob.create!(
      :first_name => "First",
      :comments => "initial"
    )
    @employee.should be_valid
    @employee.reload
    @employee.comments.should == 'initial'
    @employee.comments = "changed"
    @employee.save.should == true
    @employee.reload
    @employee.comments.should == 'initial'
  end

  it "should work for serialized readonly CLOB columns", serialized: true do
    @employee = TestSerializeEmployee.new(
      :first_name => "First",
      :comments => nil
    )
    @employee.comments.should be_nil
    @employee.save.should == true
    @employee.should be_valid
    @employee.reload
    @employee.comments.should be_nil
    @employee.comments = {}
    @employee.save.should == true
    @employee.reload
    #should not set readonly
    @employee.comments.should be_nil
  end


  it "should create record with CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => @char_data
    )
    @employee.reload
    @employee.comments.should == @char_data
  end

  it "should update record with CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.comments.should be_nil
    @employee.comments = @char_data
    @employee.save!
    @employee.reload
    @employee.comments.should == @char_data
  end

  it "should update record with zero-length CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.comments.should be_nil
    @employee.comments = ''
    @employee.save!
    @employee.reload
    @employee.comments.should == ''
  end

  it "should update record that has existing CLOB data with different CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => @char_data
    )
    @employee.reload
    @employee.comments = @char_data2
    @employee.save!
    @employee.reload
    @employee.comments.should == @char_data2
  end

  it "should update record that has existing CLOB data with nil" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => @char_data
    )
    @employee.reload
    @employee.comments = nil
    @employee.save!
    @employee.reload
    @employee.comments.should be_nil
  end

  it "should update record that has existing CLOB data with zero-length CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => @char_data
    )
    @employee.reload
    @employee.comments = ''
    @employee.save!
    @employee.reload
    @employee.comments.should == ''
  end

  it "should update record that has zero-length CLOB data with non-empty CLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => ''
    )
    @employee.reload
    @employee.comments.should == ''
    @employee.comments = @char_data
    @employee.save!
    @employee.reload
    @employee.comments.should == @char_data
  end

  it "should store serializable ruby data structures" do
    ruby_data1 = {"arbitrary1" => ["ruby", :data, 123]}
    ruby_data2 = {"arbitrary2" => ["ruby", :data, 123]}
    @employee = Test2Employee.create!(
      :comments => ruby_data1
    )
    @employee.reload
    @employee.comments.should == ruby_data1
    @employee.comments = ruby_data2
    @employee.save
    @employee.reload
    @employee.comments.should == ruby_data2
  end

  it "should keep unchanged serialized data when other columns changed" do
    @employee = Test2Employee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => "initial serialized data"
    )
    @employee.first_name = "Steve"
    @employee.save
    @employee.reload
    @employee.comments.should == "initial serialized data"
  end

  it "should keep serialized data after save" do
    @employee = Test2Employee.new
    @employee.comments = {:length=>{:is=>1}}
    @employee.save
    @employee.reload
    @employee.comments.should == {:length=>{:is=>1}}
    @employee.comments = {:length=>{:is=>2}}
    @employee.save
    @employee.reload
    @employee.comments.should == {:length=>{:is=>2}}
  end
end

describe "OracleEnhancedAdapter handling of BLOB columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        binary_data   BLOB
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    @binary_data = "\0\1\2\3\4\5\6\7\8\9"*10000
    @binary_data2 = "\1\2\3\4\5\6\7\8\9\0"*10000
  end

  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  before(:each) do
    class ::TestEmployee < ActiveRecord::Base
      self.primary_key = "employee_id"
    end
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  it "should create record with BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data.should == @binary_data
  end

  it "should update record with BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.binary_data.should be_nil
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data
  end

  it "should update record with zero-length BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.binary_data.should be_nil
    @employee.binary_data = ''
    @employee.save!
    @employee.reload
    @employee.binary_data.should == ''
  end

  it "should update record that has existing BLOB data with different BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = @binary_data2
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data2
  end

  it "should update record that has existing BLOB data with nil" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = nil
    @employee.save!
    @employee.reload
    @employee.binary_data.should be_nil
  end

  it "should update record that has existing BLOB data with zero-length BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = ''
    @employee.save!
    @employee.reload
    @employee.binary_data.should == ''
  end

  it "should update record that has zero-length BLOB data with non-empty BLOB data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => ''
    )
    @employee.reload
    @employee.binary_data.should == ''
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data
  end
end

describe "OracleEnhancedAdapter handling of RAW columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        binary_data   RAW(1024)
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    @binary_data = "\0\1\2\3\4\5\6\7\8\9"*100
    @binary_data2 = "\1\2\3\4\5\6\7\8\9\0"*100
  end

  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  before(:each) do
    class ::TestEmployee < ActiveRecord::Base
      self.primary_key = "employee_id"
    end
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  it "should create record with RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data.should == @binary_data
  end

  it "should update record with RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.binary_data.should be_nil
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data
  end

  it "should update record with zero-length RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.reload
    @employee.binary_data.should be_nil
    @employee.binary_data = ''
    @employee.save!
    @employee.reload
    @employee.binary_data.should.nil?
  end

  it "should update record that has existing RAW data with different RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = @binary_data2
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data2
  end

  it "should update record that has existing RAW data with nil" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = nil
    @employee.save!
    @employee.reload
    @employee.binary_data.should be_nil
  end

  it "should update record that has existing RAW data with zero-length RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => @binary_data
    )
    @employee.reload
    @employee.binary_data = ''
    @employee.save!
    @employee.reload
    @employee.binary_data.should.nil?
  end

  it "should update record that has zero-length BLOB data with non-empty RAW data" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :binary_data => ''
    )
    @employee.reload
    @employee.binary_data = @binary_data
    @employee.save!
    @employee.reload
    @employee.binary_data.should == @binary_data
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
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  it "should set nchar instance variable" do
    columns = @conn.columns('test_items')
    %w(nchar_column nvarchar2_column char_column varchar2_column).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type.should == :string
      column.nchar.should == (col[0,1] == 'n' ? true : nil)
    end
  end

  it "should quote with N prefix" do
    columns = @conn.columns('test_items')
    %w(nchar_column nvarchar2_column char_column varchar2_column).each do |col|
      column = columns.detect{|c| c.name == col}
      @conn.quote('abc', column).should == (column.nchar ? "N'abc'" : "'abc'")
      @conn.quote(nil, column).should == 'NULL'
    end
  end

  it "should create record" do
    nchar_data = 'āčē'
    item = TestItem.create(
      :nchar_column => nchar_data,
      :nvarchar2_column => nchar_data
    ).reload
    item.nchar_column.should == nchar_data + ' '*17
    item.nvarchar2_column.should == nchar_data
  end

end

describe "OracleEnhancedAdapter handling of BINARY_FLOAT columns" do
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
        hourly_rate   BINARY_FLOAT,
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

    class ::Test2Employee < ActiveRecord::Base
    end
  end
  
  after(:all) do
    Object.send(:remove_const, "Test2Employee")

    @conn.execute "DROP TABLE test2_employees"
    @conn.execute "DROP SEQUENCE test2_employees_seq"
  end

  it "should set BINARY_FLOAT column type as float" do
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "hourly_rate"}
    column.type.should == :float
  end

  it "should BINARY_FLOAT column type returns an approximate value" do
    employee = Test2Employee.create(hourly_rate: 4.4)

    employee.reload

    expect(employee.hourly_rate).to eq(4.400000095367432)
  end
end
