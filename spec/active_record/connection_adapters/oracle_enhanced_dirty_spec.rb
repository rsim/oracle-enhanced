require 'spec_helper'

if ActiveRecord::Base.method_defined?(:changed?)

  describe "OracleEnhancedAdapter dirty object tracking" do

    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.connection
      @conn.execute "DROP TABLE test_employees" rescue nil
      @conn.execute "DROP SEQUENCE test_employees_seq" rescue nil
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          id            NUMBER PRIMARY KEY,
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          job_id        NUMBER(6,0) NULL,
          salary        NUMBER(8,2),
          comments      CLOB,
          hire_date     DATE
        )
      SQL
      @conn.execute <<-SQL
        CREATE SEQUENCE test_employees_seq  MINVALUE 1
          INCREMENT BY 1 CACHE 20 NOORDER NOCYCLE
      SQL
      class TestEmployee < ActiveRecord::Base
      end
    end
  
    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      @conn.execute "DROP TABLE test_employees"
      @conn.execute "DROP SEQUENCE test_employees_seq"
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end  

    it "should not mark empty string (stored as NULL) as changed when reassigning it" do
      @employee = TestEmployee.create!(:first_name => '')
      @employee.first_name = ''
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.first_name = ''
      expect(@employee).not_to be_changed
    end

    it "should not mark empty integer (stored as NULL) as changed when reassigning it" do
      @employee = TestEmployee.create!(:job_id => '')
      @employee.job_id = ''
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.job_id = ''
      expect(@employee).not_to be_changed
    end

    it "should not mark empty decimal (stored as NULL) as changed when reassigning it" do
      @employee = TestEmployee.create!(:salary => '')
      @employee.salary = ''
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.salary = ''
      expect(@employee).not_to be_changed
    end

    it "should not mark empty text (stored as NULL) as changed when reassigning it" do
      @employee = TestEmployee.create!(:comments => nil)
      @employee.comments = nil
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.comments = nil
      expect(@employee).not_to be_changed
    end

    it "should not mark empty text (stored as empty_clob()) as changed when reassigning it" do
      @employee = TestEmployee.create!(:comments => '')
      @employee.comments = ''
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.comments = ''
      expect(@employee).not_to be_changed
    end

    it "should mark empty text (stored as empty_clob()) as changed when assigning nil to it" do
      @employee = TestEmployee.create!(:comments => '')
      @employee.comments = nil
      expect(@employee).to be_changed
      @employee.reload
      @employee.comments = nil
      expect(@employee).to be_changed
    end

    it "should mark empty text (stored as NULL) as changed when assigning '' to it" do
      @employee = TestEmployee.create!(:comments => nil)
      @employee.comments = ''
      expect(@employee).to be_changed
      @employee.reload
      @employee.comments = ''
      expect(@employee).to be_changed
    end

    it "should not mark empty date (stored as NULL) as changed when reassigning it" do
      @employee = TestEmployee.create!(:hire_date => '')
      @employee.hire_date = ''
      expect(@employee).not_to be_changed
      @employee.reload
      @employee.hire_date = ''
      expect(@employee).not_to be_changed
    end

    it "should not mark integer as changed when reassigning it" do
      @employee = TestEmployee.new
      @employee.job_id = 0
      expect(@employee.save!).to be_truthy
      
      expect(@employee).not_to be_changed

      @employee.job_id = '0'
      expect(@employee).not_to be_changed
    end

    it "should not update unchanged CLOBs" do
      @employee = TestEmployee.create!(
          :comments => "initial"
      )
      expect(@employee.save!).to be_truthy
      @employee.reload
      expect(@employee.comments).to eq('initial')

      oci_conn = @conn.instance_variable_get('@connection')
      class << oci_conn
         def write_lob(lob, value, is_binary = false); raise "don't do this'"; end
      end
      expect{@employee.save!}.not_to raise_exception(RuntimeError, "don't do this'")
      class << oci_conn
        remove_method :write_lob
      end
    end

    it "should be able to handle attributes which are not backed by a column" do
      TestEmployee.create!(:comments => "initial")
      @employee = TestEmployee.select("#{TestEmployee.quoted_table_name}.*, 24 ranking").first
      expect { @employee.ranking = 25 }.to_not raise_error
    end
  end

end
