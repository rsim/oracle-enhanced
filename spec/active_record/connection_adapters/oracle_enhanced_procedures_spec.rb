require 'spec_helper'

require 'ruby-plsql'

describe "OracleEnhancedAdapter custom methods for create, update and destroy" do
  include LoggerSpecHelper
  
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    plsql.activerecord_class = ActiveRecord::Base
    @conn.execute("DROP TABLE test_employees") rescue nil
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        employee_id   NUMBER(6,0) PRIMARY KEY,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        hire_date     DATE,
        salary        NUMBER(8,2),
        description   CLOB,
        version       NUMBER(15,0),
        create_time   DATE,
        update_time   DATE,
        created_at    DATE,
        updated_at    DATE
      )
    SQL
    @conn.execute("DROP SEQUENCE test_employees_s") rescue nil
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
            p_description   VARCHAR2,
            p_employee_id   OUT NUMBER);
        PROCEDURE update_employee(
            p_employee_id   NUMBER,
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER,
            p_description   VARCHAR2);
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
            p_description   VARCHAR2,
            p_employee_id   OUT NUMBER)
        IS
        BEGIN
          SELECT test_employees_s.NEXTVAL INTO p_employee_id FROM dual;
          INSERT INTO test_employees (employee_id, first_name, last_name, hire_date, salary, description,
                                      version, create_time, update_time)
          VALUES (p_employee_id, p_first_name, p_last_name, p_hire_date, p_salary, p_description,
                                      1, SYSDATE, SYSDATE);
        END create_employee;
        
        PROCEDURE update_employee(
            p_employee_id   NUMBER,
            p_first_name    VARCHAR2,
            p_last_name     VARCHAR2,
            p_hire_date     DATE,
            p_salary        NUMBER,
            p_description   VARCHAR2)
        IS
            v_version       NUMBER;
        BEGIN
          SELECT version INTO v_version FROM test_employees WHERE employee_id = p_employee_id FOR UPDATE;
          UPDATE test_employees
          SET first_name = p_first_name, last_name = p_last_name,
              hire_date = p_hire_date, salary = p_salary, description = p_description,
              version = v_version + 1, update_time = SYSDATE
          WHERE employee_id = p_employee_id;
        END update_employee;
        
        PROCEDURE delete_employee(
            p_employee_id   NUMBER)
        IS
        BEGIN
          DELETE FROM test_employees WHERE employee_id = p_employee_id;
        END delete_employee;
      END;
    SQL

    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_dates_by_column_name = true
  end

  after(:all) do
    @conn = ActiveRecord::Base.connection
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_s"
    @conn.execute "DROP PACKAGE test_employees_pkg"
  end

  before(:each) do
    class ::TestEmployee < ActiveRecord::Base
      include ActiveRecord::OracleEnhancedProcedures
      self.primary_key = :employee_id

      validates_presence_of :first_name, :last_name, :hire_date
      
      # should return ID of new record
      set_create_method do
        plsql.test_employees_pkg.create_employee(
          :p_first_name => first_name,
          :p_last_name => last_name,
          :p_hire_date => hire_date,
          :p_salary => salary,
          :p_description => "#{first_name} #{last_name}",
          :p_employee_id => nil
        )[:p_employee_id]
      end

      # return value is ignored
      set_update_method do
        plsql.test_employees_pkg.update_employee(
          :p_employee_id => id,
          :p_first_name => first_name,
          :p_last_name => last_name,
          :p_hire_date => hire_date,
          :p_salary => salary,
          :p_description => "#{first_name} #{last_name}"
        )
      end

      # return value is ignored
      set_delete_method do
        plsql.test_employees_pkg.delete_employee(
          :p_employee_id => id
        )
      end

      private

      def raise_make_transaction_rollback
        raise "Make the transaction rollback"
      end
    end

    @today = Date.new(2008,6,28)
    @buffer = StringIO.new
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
  end

  it "should create record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    expect(@employee.first_name).to eq("First")
    expect(@employee.last_name).to eq("Last")
    expect(@employee.hire_date).to eq(@today)
    expect(@employee.description).to eq("First Last")
    expect(@employee.create_time).not_to be_nil
    expect(@employee.update_time).not_to be_nil
  end

  it "should rollback record when exception is raised in after_create callback" do
    TestEmployee.after_create :raise_make_transaction_rollback

    @employee = TestEmployee.new(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    employees_count = TestEmployee.count
    expect {
      @employee.save
    }.to raise_error("Make the transaction rollback")
    expect(@employee.id).to eq(nil)
    expect(TestEmployee.count).to eq(employees_count)
  end

  it "should update record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today,
      :description => "description"
    )
    @employee.reload
    @employee.first_name = "Second"
    @employee.save!
    @employee.reload
    expect(@employee.description).to eq("Second Last")
  end

  it "should rollback record when exception is raised in after_update callback" do
    TestEmployee.after_update :raise_make_transaction_rollback

    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today,
      :description => "description"
    )
    empl_id = @employee.id
    @employee.reload
    @employee.first_name = "Second"
    expect {
      @employee.save
    }.to raise_error("Make the transaction rollback")
    @employee.reload
    expect(@employee.first_name).to eq("First")
  end

  it "should not update record if nothing is changed and partial writes are enabled" do
    TestEmployee.partial_writes = true
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    @employee.save!
    @employee.reload
    expect(@employee.version).to eq(1)
  end

  it "should update record if nothing is changed and partial writes are disabled" do
    TestEmployee.partial_writes = false
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    @employee.save!
    @employee.reload
    expect(@employee.version).to eq(2)
  end

  it "should delete record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    empl_id = @employee.id
    @employee.destroy
    expect(@employee).to be_frozen
    expect(TestEmployee.find_by_employee_id(empl_id)).to be_nil
  end

  it "should delete record and set destroyed flag" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    @employee.destroy
    expect(@employee).to be_destroyed
  end

  it "should rollback record when exception is raised in after_destroy callback" do
    set_logger
    TestEmployee.after_destroy :raise_make_transaction_rollback

    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    empl_id = @employee.id
    expect {
      @employee.destroy
    }.to raise_error("Make the transaction rollback")
    expect(@employee.id).to eq(empl_id)
    expect(TestEmployee.find_by_employee_id(empl_id)).not_to be_nil
    clear_logger
  end

  it "should set timestamps when creating record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    expect(@employee.created_at).not_to be_nil
    expect(@employee.updated_at).not_to be_nil
  end

  it "should set timestamps when updating record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.reload
    expect(@employee.created_at).to be_nil
    expect(@employee.updated_at).to be_nil
    @employee.first_name = "Second"
    @employee.save!
    expect(@employee.created_at).to be_nil
    expect(@employee.updated_at).not_to be_nil
  end

  it "should log create record" do
    set_logger
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    expect(@logger.logged(:debug).last).to match(/^TestEmployee Create \(\d+\.\d+(ms)?\)  custom create method$/)
    clear_logger
  end

  it "should log update record" do
    (TestEmployee.partial_writes = false) rescue nil
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    set_logger
    @employee.save!
    expect(@logger.logged(:debug).last).to match(/^TestEmployee Update \(\d+\.\d+(ms)?\)  custom update method with employee_id=#{@employee.id}$/)
    clear_logger
  end

  it "should log delete record" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    set_logger
    @employee.destroy
    expect(@logger.logged(:debug).last).to match(/^TestEmployee Destroy \(\d+\.\d+(ms)?\)  custom delete method with employee_id=#{@employee.id}$/)
    clear_logger
  end

  it "should validate new record before creation" do
    @employee = TestEmployee.new(
      :last_name => "Last",
      :hire_date => @today
    )
    expect(@employee.save).to be_falsey
    expect(@employee.errors[:first_name]).not_to be_blank
  end

  it "should validate existing record before update" do
    @employee = TestEmployee.create(
      :first_name => "First",
      :last_name => "Last",
      :hire_date => @today
    )
    @employee.first_name = nil
    expect(@employee.save).to be_falsey
    expect(@employee.errors[:first_name]).not_to be_blank
  end
  
end
