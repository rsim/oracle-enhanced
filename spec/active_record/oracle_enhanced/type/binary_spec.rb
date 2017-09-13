# frozen_string_literal: true

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
