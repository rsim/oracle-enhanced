require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe "OracleEnhancedAdapter custom methods for create, update and destroy" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    plsql.connection = @conn.raw_connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0),
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        hire_date     DATE,
        salary        NUMBER(8,2),
        create_time   DATE,
        update_time   DATE
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_s  MINVALUE 1
        INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
    SQL
    @conn.execute <<-SQL
      CREATE OR REPLACE PACKAGE test_employees_pkg IS
        PROCEDURE create_employee(
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER,
            p_employee_id   OUT NUMBER);
        PROCEDURE update_employee(
            p_employee_id   NUMBER,
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER);
        PROCEDURE delete_employee(
            p_employee_id   NUMBER);
      END;
    SQL
    @conn.execute <<-SQL
      CREATE OR REPLACE PACKAGE BODY test_employees_pkg IS
        PROCEDURE create_employee(
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER,
            p_employee_id   OUT NUMBER)
        IS
        BEGIN
          SELECT test_employees_s.NEXTVAL INTO p_employee_id FROM dual;
          INSERT INTO test_employees (employee_id, first_name, last_name, hire_date, salary, create_time, update_time)
          VALUES (p_employee_id, p_first_name, p_last_name, p_hire_date, p_salary, SYSDATE, SYSDATE);
        END create_employee;
        
        PROCEDURE update_employee(
            p_employee_id   NUMBER,
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER)
        IS
        BEGIN
          RETURN;
        END update_employee;
        
        PROCEDURE delete_employee(
            p_employee_id   NUMBER)
        IS
        BEGIN
          RETURN;
        END delete_employee;
      END;
    SQL

    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true

    class TestEmployee < ActiveRecord::Base
      set_primary_key :employee_id
      
      set_create_method do
        plsql.test_employees_pkg.create_employee(
          :p_first_name => first_name,
          :p_last_name => last_name,
          :p_hire_date => hire_date,
          :p_salary => salary,
          :p_employee_id => nil
        )[:p_employee_id]
      end

    end
  end
  
  after(:all) do
    Object.send(:remove_const, "TestEmployee")
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_s"
    # @conn.execute "DROP PACKAGE test_employees_pkg"
  end

  before(:each) do
    @today = Date.new(2008,6,28)
    @now = Time.local(2008,6,28,13,34,33)
  end

  it "should create employee" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    @employee.first_name.should == "First"
    @employee.last_name.should == "Last"
    @employee.hire_date.should == @today
    @employee.create_time.should_not be_nil
    @employee.update_time.should_not be_nil
  end

end
