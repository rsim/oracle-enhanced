# frozen_string_literal: true

describe "OracleEnhancedAdapter handling of DECIMAL columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
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
        t.decimal :hourly_rate
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

  it "should set DECIMAL column type as decimal" do
    columns = @conn.columns("test2_employees")
    column = columns.detect { |c| c.name == "hourly_rate" }
    expect(column.type).to eq(:decimal)
  end

  it "should DECIMAL column type returns an exact value" do
    employee = Test2Employee.create(hourly_rate: 4.40125)

    employee.reload

    expect(employee.hourly_rate).to eq(4.40125)
  end

  it "should DECIMAL column type rounds if scale is specified and value exceeds scale" do
    employee = Test2Employee.create(commission_pct: 0.1575)

    employee.reload

    expect(employee.commission_pct).to eq(0.16)
  end
end
