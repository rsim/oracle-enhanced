# frozen_string_literal: true

describe "compatibility migrations" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_employees, if_exists: true
      drop_table :new_test_employees, if_exists: true
    end
  end

  it "should rename table on 7_0 and below" do
    migration = Class.new(ActiveRecord::Migration[7.0]) {
      def change
        rename_table :test_employees, :new_test_employees
      end
    }.new

    migration.migrate(:up)
    expect(@conn.table_exists?(:new_test_employees)).to be_truthy
    expect(@conn.table_exists?(:test_employees)).not_to be_truthy

    migration.migrate(:down)
    expect(@conn.table_exists?(:new_test_employees)).not_to be_truthy
    expect(@conn.table_exists?(:test_employees)).to be_truthy
  end
end
