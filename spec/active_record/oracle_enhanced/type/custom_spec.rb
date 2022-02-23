# frozen_string_literal: true

require "base64"

describe "OracleEnhancedAdapter custom types handling" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_employees, force: true do |t|
        t.string    :first_name,  limit: 20
        t.string    :last_name,   limit: 25
        t.text      :signature
      end
    end

    class TestEmployee < ActiveRecord::Base
      class AttributeSignature < ActiveRecord::Type::Text
        def cast(value)
          case value
          when Signature
            value
          when nil
            nil
          else
            Signature.new(Base64.decode64 value)
          end
        end

        def serialize(value)
          Base64.encode64 value.raw
        end

        def changed_in_place?(raw_old_value, new_value)
          new_value != cast(raw_old_value)
        end
      end

      class Signature
        attr_reader :raw

        def initialize(raw_value)
          @raw = raw_value
        end

        def to_s
          "Signature nice string #{raw[0..5]}"
        end

        def ==(object)
          raw == object&.raw
        end
        alias eql? ==
      end

      attribute :signature, AttributeSignature.new
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_employees
    end
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should serialize LOBs when creating a record" do
    raw_signature = "peter'ssignature"
    signature = TestEmployee::Signature.new(raw_signature)
    @employee = TestEmployee.create!(first_name: "Peter", last_name: "Doe", signature: signature)
    @employee.reload
    expect(@employee.signature).to eql(signature)
    expect(@employee.signature).to_not be(signature)
    expect(TestEmployee.first.read_attribute_before_type_cast(:signature)).to eq(Base64.encode64 raw_signature)
  end

  it "should serialize LOBs when updating a record" do
    raw_signature = "peter'ssignature"
    signature = TestEmployee::Signature.new(raw_signature)
    @employee = TestEmployee.create!(first_name: "Peter", last_name: "Doe", signature: TestEmployee::Signature.new("old signature"))
    @employee.signature = signature
    @employee.save!
    @employee.reload
    expect(@employee.signature).to eql(signature)
    expect(@employee.signature).to_not be(signature)
    expect(TestEmployee.first.read_attribute_before_type_cast(:signature)).to eq(Base64.encode64 raw_signature)
  end
end
