require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe "OracleEnhancedAdapter establish connection" do
  
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
  end
  
  it "should connect to database" do
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end
  
end

describe "OracleEnhancedAdapter schema dump" do
  
  before(:all) do
    @old_conn = ActiveRecord::Base.oracle_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @old_conn.class.should == ActiveRecord::ConnectionAdapters::OracleAdapter
    @new_conn = ActiveRecord::Base.oracle_enhanced_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @new_conn.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should return the same tables list as original oracle adapter" do
    @new_conn.tables.should == @old_conn.tables
  end

  it "should return the same index list as original oracle adapter" do
    @new_conn.indexes('employees').should == @old_conn.indexes('employees')
  end

  it "should return the same pk_and_sequence_for as original oracle adapter" do
    @new_conn.tables.each do |t|
      @new_conn.pk_and_sequence_for(t).should == @old_conn.pk_and_sequence_for(t)
    end    
  end

  it "should return the same structure dump as original oracle adapter" do
    @new_conn.structure_dump.should == @old_conn.structure_dump
  end

  it "should return the same structure drop as original oracle adapter" do
    @new_conn.structure_drop.should == @old_conn.structure_drop
  end
  
  it "should return the character size of nvarchar fields" do
    @new_conn.execute <<-SQL
      CREATE TABLE nvarchartable (
        session_id  NVARCHAR2(255) DEFAULT NULL
      )
    SQL
    if /.*session_id nvarchar2\((\d+)\).*/ =~ @new_conn.structure_dump
       "#$1".should == "255"
    end
    @new_conn.execute "DROP TABLE nvarchartable"
  end
end

describe "OracleEnhancedAdapter database stucture dump extentions" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE nvarchartable (
        unq_nvarchar  NVARCHAR2(255) DEFAULT NULL
      )
    SQL
  end
  
  after(:all) do
    @conn.execute "DROP TABLE nvarchartable"
  end
  
  it "should return the character size of nvarchar fields" do
    if /.*unq_nvarchar nvarchar2\((\d+)\).*/ =~ @conn.structure_dump
       "#$1".should == "255"
    end
  end
end

describe "OracleEnhancedAdapter database session store" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE sessions (
        id          NUMBER(38,0) NOT NULL,
        session_id  VARCHAR2(255) DEFAULT NULL,
        data        CLOB DEFAULT NULL,
        created_at  DATE DEFAULT NULL,
        updated_at  DATE DEFAULT NULL,
        PRIMARY KEY (ID)
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE sessions_seq  MINVALUE 1 MAXVALUE 999999999999999999999999999
        INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE sessions"
    @conn.execute "DROP SEQUENCE sessions_seq"
  end

  it "should create sessions table" do
    ActiveRecord::Base.connection.tables.grep("sessions").should_not be_empty
  end

  it "should save session data" do
    @session = CGI::Session::ActiveRecordStore::Session.new :session_id => "111111", :data  => "something" #, :updated_at => Time.now
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("111111")
    @session.data.should == "something"
  end

  it "should change session data when partial updates enabled" do
    return pending("Not in this ActiveRecord version") unless CGI::Session::ActiveRecordStore::Session.respond_to?(:partial_updates=)
    CGI::Session::ActiveRecordStore::Session.partial_updates = true
    @session = CGI::Session::ActiveRecordStore::Session.new :session_id => "222222", :data  => "something" #, :updated_at => Time.now
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("222222")
    @session.data = "other thing"
    @session.save!
    # second save should call again blob writing callback
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("222222")
    @session.data.should == "other thing"
  end

  it "should have one enhanced_write_lobs callback" do
    return pending("Not in this ActiveRecord version") unless CGI::Session::ActiveRecordStore::Session.respond_to?(:after_save_callback_chain)
    CGI::Session::ActiveRecordStore::Session.after_save_callback_chain.select{|cb| cb.method == :enhanced_write_lobs}.should have(1).record
  end

  it "should not set sessions table session_id column type as integer if emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('sessions')
    column = columns.detect{|c| c.name == "session_id"}
    column.type.should == :string
  end

end

describe "OracleEnhancedAdapter date type detection based on column names" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
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
    column.type_cast(Time.now).class.should == Time
  end

  it "should return Date value from DATE column if column name contains 'date' and emulate_dates_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
    columns = @conn.columns('test_employees')
    column = columns.detect{|c| c.name == "hire_date"}
    column.type_cast(Time.now).class.should == Date
  end

  describe "/ DATE values from ActiveRecord model" do
    before(:each) do
      ActiveRecord::Base.connection.clear_types_for_columns
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates = false
      class TestEmployee < ActiveRecord::Base
        set_table_name "hr.test_employees"
        set_primary_key :employee_id
      end
    end
    
    def create_test_employee
      @today = Date.new(2008,8,19)
      @now = Time.local(2008,8,19,17,03,59)
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

    it "should return Time value from DATE column if column name does not contain 'date' and emulate_dates_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
      create_test_employee
      @employee.created_at.class.should == Time
    end

    it "should return Date value from DATE column if emulate_dates_by_column_name is false but column is defined as date" do
      class TestEmployee < ActiveRecord::Base
        set_date_columns :hire_date
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = false
      create_test_employee
      @employee.hire_date.class.should == Date
    end

    it "should return Time value from DATE column if emulate_dates_by_column_name is true but column is defined as datetime" do
      class TestEmployee < ActiveRecord::Base
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
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test2_employees (
        id   NUMBER,
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
        created_at    DATE
      )
    SQL
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
    column.type_cast(1.0).class.should == BigDecimal
  end

  it "should return Fixnum value from NUMBER column if column name contains 'id' and emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('test2_employees')
    column = columns.detect{|c| c.name == "job_id"}
    column.type_cast(1.0).class.should == Fixnum
  end

  describe "/ NUMBER values from ActiveRecord model" do
    before(:each) do
      class Test2Employee < ActiveRecord::Base
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "Test2Employee")
    end
    
    def create_employee2
      @employee2 = Test2Employee.create(
        :first_name => "First",
        :last_name => "Last",
        :job_id => 1,
        :salary => 1000
      )
      @employee2.reload
    end
    
    it "should return BigDecimal value from NUMBER column if emulate_integers_by_column_name is false" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = false
      create_employee2
      @employee2.job_id.class.should == BigDecimal
    end

    it "should return Fixnum value from NUMBER column if column name contains 'id' and emulate_integers_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      create_employee2
      @employee2.job_id.class.should == Fixnum
    end

    it "should return BigDecimal value from NUMBER column if column name does not contain 'id' and emulate_integers_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      create_employee2
      @employee2.salary.class.should == BigDecimal
    end

  end

end

describe "OracleEnhancedAdapter boolean type detection based on string column types and names" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test3_employees (
        id            NUMBER,
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
        has_phone     VARCHAR2(1),
        active_flag   VARCHAR2(2),
        manager_yn    VARCHAR2(3),
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
      column.type_cast("Y").class.should == String
    end
  end
  
  it "should return boolean value from VARCHAR2 boolean column if emulate_booleans_from_strings is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = true
    columns = @conn.columns('test3_employees')
    %w(has_email has_phone active_flag manager_yn).each do |col|
      column = columns.detect{|c| c.name == col}
      column.type_cast("Y").class.should == TrueClass
      column.type_cast("N").class.should == FalseClass
    end
  end
  
  describe "/ VARCHAR2 boolean values from ActiveRecord model" do
    before(:each) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_booleans_from_strings = false
      class Test3Employee < ActiveRecord::Base
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "Test3Employee")
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
      class Test3Employee < ActiveRecord::Base
        set_boolean_columns :test_boolean
      end
      create_employee3(:test_boolean => true)
      @employee3.test_boolean.class.should == TrueClass
      @employee3.test_boolean_before_type_cast.should == "Y"
      create_employee3(:test_boolean => false)
      @employee3.test_boolean.class.should == FalseClass
      @employee3.test_boolean_before_type_cast.should == "N"
    end
  
  end

end


describe "OracleEnhancedAdapter ignore specified table columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        id            NUMBER,
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
        created_at    DATE
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 START WITH 1 CACHE 20 NOORDER NOCYCLE
    SQL
  end
  
  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
  end

  it "should ignore specified table columns" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number, :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
  end

  it "should ignore specified table columns specified in several lines" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number
      ignore_table_columns  :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
  end

  it "should not ignore unspecified table columns" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number, :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| c.name == 'email' }.should_not be_empty
  end


end


describe "OracleEnhancedAdapter timestamp with timezone support" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
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
      class TestEmployee < ActiveRecord::Base
        set_primary_key :employee_id
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
    end

    it "should return Time value from TIMESTAMP columns" do
      # currently fractional seconds are not retrieved from database
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

    it "should return Time value without fractional seconds from TIMESTAMP columns" do
      # currently fractional seconds are not retrieved from database
      @now = Time.local(2008,5,26,23,11,11,10)
      @employee = TestEmployee.create(
        :created_at => @now,
        :created_at_tz => @now,
        :created_at_ltz => @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        @employee.send(c).class.should == Time
        @employee.send(c).to_f.should == @now.to_f.to_i.to_f # remove fractional seconds
      end
    end

  end

end


describe "OracleEnhancedAdapter date and timestamp with different NLS date formats" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
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
    class TestEmployee < ActiveRecord::Base
      set_primary_key :employee_id
    end
    @today = Date.new(2008,6,28)
    @now = Time.local(2008,6,28,13,34,33)
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")    
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
    @ts = Time.at(@now.to_f + 0.1)
    @conn.quote(@ts).should == "TO_TIMESTAMP('#{@ts.year}-#{"%02d" % @ts.month}-#{"%02d" % @ts.day} "+
                                "#{"%02d" % @ts.hour}:#{"%02d" % @ts.min}:#{"%02d" % @ts.sec}.100000','YYYY-MM-DD HH24:MI:SS.FF6')"
  end

end

describe "OracleEnhancedAdapter assign string to :date and :datetime columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
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
    class TestEmployee < ActiveRecord::Base
      set_primary_key :employee_id
    end
  end
  
  after(:all) do
    Object.send(:remove_const, "TestEmployee")
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  before(:each) do
    @today = Date.new(2008,6,28)
    @today_iso = "2008-06-28"
    @today_nls = "28.06.2008"
    @nls_date_format = "%d.%m.%Y"
    @now = Time.local(2008,6,28,13,34,33)
    @now_iso = "2008-06-28 13:34:33"
    @now_nls = "28.06.2008 13:34:33"
    @nls_time_format = "%d.%m.%Y %H:%M:%S"
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
  end
  
  it "should assign ISO string to date column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today_iso
    )
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
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign ISO time string to date column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @now_iso
    )
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
    @employee.reload
    @employee.hire_date.should == @today
  end

  it "should assign ISO time string to datetime column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @now_iso
    )
    @employee.reload
    @employee.last_login_at.should == @now
  end

  it "should assign NLS time string to datetime column" do
    # ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_date_format = @nls_date_format
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.string_to_time_format = @nls_time_format
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @now_nls
    )
    @employee.reload
    @employee.last_login_at.should == @now
  end
  
  it "should assign ISO date string to datetime column" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :last_login_at => @today_iso
    )
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
    @employee.reload
    @employee.last_login_at.should == @today.to_time
  end
  
end

describe "OracleEnhancedAdapter handling of CLOB columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        comments      CLOB
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    class TestEmployee < ActiveRecord::Base
      set_primary_key :employee_id
    end
  end
  
  after(:all) do
    Object.send(:remove_const, "TestEmployee")
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  before(:each) do
  end
  
  it "should create record without CLOB data when attribute is serialized" do
    TestEmployee.serialize :comments
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last"
    )
    @employee.should be_valid
  end

  it "should order by CLOB column" do
    @employee = TestEmployee.create!(
      :first_name => "First",
      :last_name => "Last",
      :comments => "comments"
    )
    TestEmployee.find(:all, :order => "comments ASC").should_not be_empty
    TestEmployee.find(:all, :order => " comments ASC ").should_not be_empty
    TestEmployee.find(:all, :order => "comments").should_not be_empty
    TestEmployee.find(:all, :order => " comments ").should_not be_empty
    TestEmployee.find(:all, :order => :comments).should_not be_empty
    TestEmployee.find(:all, :order => "  first_name DESC,  last_name   ASC   ").should_not be_empty
  end
  
end

describe "OracleEnhancedAdapter table and sequence creation with non-default primary key" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    ActiveRecord::Schema.define do
      create_table :keyboards, :force => true, :id  => false do |t|
        t.primary_key :key_number
        t.string      :name
      end
      create_table :id_keyboards, :force => true do |t|
        t.string      :name
      end
    end
    class Keyboard < ActiveRecord::Base
      set_primary_key :key_number
    end
    class IdKeyboard < ActiveRecord::Base
    end
  end
  
  after(:all) do
    ActiveRecord::Schema.define do
      drop_table :keyboards
      drop_table :id_keyboards
    end
    Object.send(:remove_const, "Keyboard")
    Object.send(:remove_const, "IdKeyboard")
  end
  
  it "should create sequence for non-default primary key" do
    ActiveRecord::Base.connection.next_sequence_value(Keyboard.sequence_name).should_not be_nil
  end

  it "should create sequence for default primary key" do
    ActiveRecord::Base.connection.next_sequence_value(IdKeyboard.sequence_name).should_not be_nil
  end
end

describe "OracleEnhancedAdapter without composite_primary_keys" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    Object.send(:remove_const, 'CompositePrimaryKeys') if defined?(CompositePrimaryKeys)
    class Employee < ActiveRecord::Base
      set_primary_key :employee_id
    end
  end

  it "should tell ActiveRecord that count distinct is supported" do
    ActiveRecord::Base.connection.supports_count_distinct?.should be_true
  end

  it "should execute correct SQL COUNT DISTINCT statement" do
    lambda { Employee.count(:employee_id, :distinct => true) }.should_not raise_error
  end

end