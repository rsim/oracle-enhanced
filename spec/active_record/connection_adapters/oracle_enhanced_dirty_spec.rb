# frozen_string_literal: true

describe "OracleEnhancedAdapter dirty object tracking" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string    :first_name,  limit: 20
        t.string    :last_name,   limit: 25
        t.integer   :job_id,      limit: 6, null: true
        t.decimal   :salary,      precision: 8, scale: 2
        t.text      :comments
        t.date      :hire_date
      end
    end

    class TestEmployee < ActiveRecord::Base
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_employees
    end
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should not mark empty string (stored as NULL) as changed when reassigning it" do
    @employee = TestEmployee.create!(first_name: "")
    @employee.first_name = ""
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.first_name = ""
    expect(@employee).not_to be_changed
  end

  it "should not mark empty integer (stored as NULL) as changed when reassigning it" do
    @employee = TestEmployee.create!(job_id: "")
    @employee.job_id = ""
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.job_id = ""
    expect(@employee).not_to be_changed
  end

  it "should not mark empty decimal (stored as NULL) as changed when reassigning it" do
    @employee = TestEmployee.create!(salary: "")
    @employee.salary = ""
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.salary = ""
    expect(@employee).not_to be_changed
  end

  it "should not mark empty text (stored as NULL) as changed when reassigning it" do
    @employee = TestEmployee.create!(comments: nil)
    @employee.comments = nil
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.comments = nil
    expect(@employee).not_to be_changed
  end

  it "should not mark empty text (stored as empty_clob()) as changed when reassigning it" do
    @employee = TestEmployee.create!(comments: "")
    @employee.comments = ""
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.comments = ""
    expect(@employee).not_to be_changed
  end

  it "should mark empty text (stored as empty_clob()) as changed when assigning nil to it" do
    @employee = TestEmployee.create!(comments: "")
    @employee.comments = nil
    expect(@employee).to be_changed
    @employee.reload
    @employee.comments = nil
    expect(@employee).to be_changed
  end

  it "should mark empty text (stored as NULL) as changed when assigning '' to it" do
    @employee = TestEmployee.create!(comments: nil)
    @employee.comments = ""
    expect(@employee).to be_changed
    @employee.reload
    @employee.comments = ""
    expect(@employee).to be_changed
  end

  it "should not mark empty date (stored as NULL) as changed when reassigning it" do
    @employee = TestEmployee.create!(hire_date: "")
    @employee.hire_date = ""
    expect(@employee).not_to be_changed
    @employee.reload
    @employee.hire_date = ""
    expect(@employee).not_to be_changed
  end

  it "should not mark integer as changed when reassigning it" do
    @employee = TestEmployee.new
    @employee.job_id = 0
    expect(@employee.save!).to be_truthy

    expect(@employee).not_to be_changed

    @employee.job_id = "0"
    expect(@employee).not_to be_changed
  end

  it "should not update unchanged CLOBs" do
    @conn = nil
    @connection = nil
    @employee = TestEmployee.create!(
      comments: "initial"
    )
    expect(@employee.save!).to be_truthy
    @employee.reload
    expect(@employee.comments).to eq("initial")

    oci_conn = @conn.instance_variable_get("@connection")
    class << oci_conn
       def write_lob(lob, value, is_binary = false); raise "don't do this'"; end
    end
    expect { @employee.save! }.not_to raise_error
    class << oci_conn
      remove_method :write_lob
    end
  end

  it "should be able to handle attributes which are not backed by a column" do
    TestEmployee.create!(comments: "initial")
    @employee = TestEmployee.select("#{TestEmployee.quoted_table_name}.*, 24 ranking").first
    expect { @employee.ranking = 25 }.to_not raise_error
  end
end
