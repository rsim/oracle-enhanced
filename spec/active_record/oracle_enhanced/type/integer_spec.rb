# frozen_string_literal: true

describe "OracleEnhancedAdapter integer type detection based on attribute settings" do
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

    it "should return BigDecimal value from NUMBER column if by default" do
      create_employee2
      expect(@employee2.job_id.class).to eq(BigDecimal)
    end

    it "should return Integer value from NUMBER column if attribute is set to integer" do
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

    it "should return Boolean value from NUMBER(1) column if emulate booleans is used" do
      create_employee2
      expect(@employee2.is_manager.class).to eq(TrueClass)
    end

    it "should return Integer value from NUMBER(1) column if attribute is set to integer" do
      class ::Test2Employee < ActiveRecord::Base
        attribute :is_manager, :integer
      end
      create_employee2
      expect(@employee2.is_manager).to be_a(Integer)
    end
  end
end
