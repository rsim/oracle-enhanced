# frozen_string_literal: true

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
