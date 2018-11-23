# frozen_string_literal: true

describe "OracleEnhancedAdapter handling of XML columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string    :first_name,    limit: 20
        t.string    :last_name,     limit: 25
        t.xmltype       :metadata
      end
    end
    @hash_data = {a: 'a'}
    @another_hash_data = {a: {b:'b', c:'c'}}
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

  it "should create record with XML data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      metadata: @hash_data
    )
    @employee.reload
    expect(@employee.metadata).to eq(@hash_data)
  end

  it "should throw exception when record has data other than xml in xml column" do
    expect { TestEmployee.create!(first_name: "First", last_name: "Last", metadata: "")}.to raise_error(/XMLTYPE column must be of type Hash/)
  end

  it "should update record that has existing XML data with different XML data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      metadata: @hash_data
    )
    @employee.reload
    @employee.metadata = @another_hash_data
    @employee.save!
    @employee.reload
    expect(@employee.metadata).to eq(@another_hash_data)
  end

end
