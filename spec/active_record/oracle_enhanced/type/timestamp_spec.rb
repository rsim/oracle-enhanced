# frozen_string_literal: true

describe "OracleEnhancedAdapter timestamp with timezone support" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.default_timezone = :local
    ActiveRecord::Base.establish_connection(CONNECTION_WITH_TIMEZONE_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string        :first_name,  limit: 20
        t.string        :last_name,  limit: 25
        t.string        :email, limit: 25
        t.string        :phone_number, limit: 20
        t.date          :hire_date
        t.decimal       :job_id, scale: 0, precision: 6
        t.decimal       :salary, scale: 2, precision: 8
        t.decimal       :commission_pct, scale: 2, precision: 2
        t.decimal       :manager_id, scale: 0, precision: 6
        t.decimal       :department_id, scale: 0, precision: 4
        t.timestamp     :created_at
        t.timestamptz   :created_at_tz
        t.timestampltz  :created_at_ltz
      end
    end
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    ActiveRecord::Base.default_timezone = :utc
  end

  describe "/ TIMESTAMP WITH TIME ZONE values from ActiveRecord model" do
    before(:all) do
      class ::TestEmployee < ActiveRecord::Base
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should return Time value from TIMESTAMP columns" do
      @now = Time.local(2008, 5, 26, 23, 11, 11, 0)
      @employee = TestEmployee.create(
        created_at: @now,
        created_at_tz: @now,
        created_at_ltz: @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        expect(@employee.send(c).class).to eq(Time)
        expect(@employee.send(c).to_f).to eq(@now.to_f)
      end
    end

    it "should return Time value with fractional seconds from TIMESTAMP columns" do
      @now = Time.local(2008, 5, 26, 23, 11, 11, 10)
      @employee = TestEmployee.create(
        created_at: @now,
        created_at_tz: @now,
        created_at_ltz: @now
      )
      @employee.reload
      [:created_at, :created_at_tz, :created_at_ltz].each do |c|
        expect(@employee.send(c).class).to eq(Time)
        expect(@employee.send(c).to_f).to eq(@now.to_f)
      end
    end

  end

end
