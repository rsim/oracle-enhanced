# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter handling of BINARY_FLOAT columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    schema_define do
      create_table :test2_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.string  :email, limit: 25
        t.string  :phone_number, limit: 25
        t.date    :hire_date
        t.integer :job_id
        t.integer :salary
        t.decimal :commission_pct, scale: 2, precision: 2
        t.float   :hourly_rate
        t.column  :hourly_rate_double, "BINARY_DOUBLE"
        t.integer :manager_id,  limit: 6
        t.integer :is_manager,  limit: 1
        t.decimal :department_id, scale: 0, precision: 4
        t.timestamps
      end
    end
    class ::Test2Employee < ActiveRecord::Base
    end
  end

  after(:all) do
    Object.send(:remove_const, "Test2Employee")
    @conn.drop_table :test2_employees, if_exists:  true
  end

  it "should set BINARY_FLOAT column type as float" do
    columns = @conn.columns("test2_employees")
    column = columns.detect { |c| c.name == "hourly_rate" }
    expect(column.type).to eq(:float)
  end

  it "should BINARY_FLOAT column type returns an approximate value" do
    employee = Test2Employee.create(hourly_rate: 4.4)

    employee.reload

    expect(employee.hourly_rate).to eq(4.400000095367432)
  end

  it "should return nil from a NULL BINARY_FLOAT column" do
    employee = Test2Employee.create(hourly_rate: nil)

    employee.reload

    expect(employee.hourly_rate).to be_nil
  end

  it "should return the value from a BINARY_DOUBLE column" do
    employee = Test2Employee.create(hourly_rate_double: 1.2345678901234567)

    employee.reload

    expect(employee.hourly_rate_double).to eq(1.2345678901234567)
  end

  it "should return nil from a NULL BINARY_DOUBLE column" do
    employee = Test2Employee.create(hourly_rate_double: nil)

    employee.reload

    expect(employee.hourly_rate_double).to be_nil
  end
end
