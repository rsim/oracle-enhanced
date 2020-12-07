# frozen_string_literal: true

describe "OracleEnhancedAdapter handling of NCLOB columns" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.ntext   :comments
      end
      create_table :test2_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
        t.ntext   :comments
      end
      create_table :test_serialize_employees, force: true do |t|
        t.string  :first_name, limit: 20
        t.string  :last_name, limit: 25
      end
      add_column :test_serialize_employees, :comments, :ntext
    end

    # Some random multibyte characters. They say Hello (Kon'nichiwa) World (Sekai) in Japanese.
    @nclob_data = "こんにちは"
    @nclob_data2 = "世界"

    class ::TestEmployee < ActiveRecord::Base; end
    class ::Test2Employee < ActiveRecord::Base
      serialize :comments
    end
    class ::TestEmployeeReadOnlyNClob < ActiveRecord::Base
      self.table_name = "test_employees"
      attr_readonly :comments
    end
    class ::TestSerializeEmployee < ActiveRecord::Base
      serialize :comments
      attr_readonly :comments
    end
  end

  after(:all) do
    @conn.drop_table :test_employees, if_exists: true
    @conn.drop_table :test2_employees, if_exists: true
    @conn.drop_table :test_serialize_employees, if_exists: true
    Object.send(:remove_const, "TestEmployee")
    Object.send(:remove_const, "Test2Employee")
    Object.send(:remove_const, "TestEmployeeReadOnlyNClob")
    Object.send(:remove_const, "TestSerializeEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should create record without NCLOB data when attribute is serialized" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last"
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should accept Symbol value for NCLOB column" do
    @employee = TestEmployee.create!(
      comments: :test_comment
    )
    expect(@employee).to be_valid
  end

  it "should respect attr_readonly setting for NCLOB column" do
    @employee = TestEmployeeReadOnlyNClob.create!(
      first_name: "First",
      comments: @nclob_data
    )
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
    @employee.comments = @nclob_data2
    expect(@employee.save).to eq(true)
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
  end

  it "should work for serialized readonly NCLOB columns", serialized: true do
    @employee = TestSerializeEmployee.new(
      first_name: "First",
      comments: nil
    )
    expect(@employee.comments).to be_nil
    expect(@employee.save).to eq(true)
    expect(@employee).to be_valid
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = {}
    expect(@employee.save).to eq(true)
    @employee.reload
    # should not set readonly
    expect(@employee.comments).to be_nil
  end

  it "should create record with NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nclob_data
    )
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
  end

  it "should update record with NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = @nclob_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
  end

  it "should update record with zero-length NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last"
    )
    @employee.reload
    expect(@employee.comments).to be_nil
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has existing NCLOB data with different NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nclob_data
    )
    @employee.reload
    @employee.comments = @nclob_data2
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data2)
  end

  it "should update record that has existing NCLOB data with nil" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nclob_data
    )
    @employee.reload
    @employee.comments = nil
    @employee.save!
    @employee.reload
    expect(@employee.comments).to be_nil
  end

  it "should update record that has existing NCLOB data with zero-length NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nclob_data
    )
    @employee.reload
    @employee.comments = ""
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq("")
  end

  it "should update record that has zero-length NCLOB data with non-empty NCLOB data" do
    @employee = TestEmployee.create!(
      first_name: "First",
      last_name: "Last",
      comments: ""
    )
    @employee.reload
    expect(@employee.comments).to eq("")
    @employee.comments = @nclob_data
    @employee.save!
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
  end

  it "should store serializable ruby data structures" do
    ruby_data1 = { "arbitrary1" => ["ruby", :data, 123] }
    ruby_data2 = { "arbitrary2" => ["ruby", :data, 123] }
    @employee = Test2Employee.create!(
      comments: ruby_data1
    )
    @employee.reload
    expect(@employee.comments).to eq(ruby_data1)
    @employee.comments = ruby_data2
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(ruby_data2)
  end

  it "should keep unchanged serialized data when other columns changed" do
    @employee = Test2Employee.create!(
      first_name: "First",
      last_name: "Last",
      comments: @nclob_data
    )
    @employee.first_name = "Steve"
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(@nclob_data)
  end

  it "should keep serialized data after save" do
    @employee = Test2Employee.new
    @employee.comments = { length: { is: 1 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 1 })
    @employee.comments = { length: { is: 2 } }
    @employee.save
    @employee.reload
    expect(@employee.comments).to eq(length: { is: 2 })
  end
end
