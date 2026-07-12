# frozen_string_literal: true

RSpec.describe "OracleEnhanced::CompatibilityBehavior resolution" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  def oracle_behavior
    ActiveRecord::ConnectionAdapters::OracleEnhanced::CompatibilityBehavior
  end

  it "resolves Migration[8.2] to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.2])).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "resolves Migration[8.1] to V8_1" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.1])).to eq oracle_behavior::V8_1
  end

  it "resolves Migration[7.0] to V8_1, which covers its own version and older" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[7.0])).to eq oracle_behavior::V8_1
  end

  it "resolves an unversioned migration to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration)).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "resolves ActiveRecord::Schema[8.1] to V8_1, like Migration[8.1]" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema[8.1])).to eq oracle_behavior::V8_1
  end

  it "resolves ActiveRecord::Schema[8.2] and plain ActiveRecord::Schema to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema[8.2])).to eq ActiveRecord::Migration::CompatibilityBehavior
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema)).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "gives a running Migration[8.1] a V8_1 behavior instance through the Rails hook" do
    migration = Class.new(ActiveRecord::Migration[8.1]).new
    expect(migration.compatibility_behavior).to be_a oracle_behavior::V8_1
  end

  it "gives a running Migration[8.2] the no-op base behavior through the Rails hook" do
    migration = Class.new(ActiveRecord::Migration[8.2]).new
    expect(migration.compatibility_behavior).to be_an_instance_of ActiveRecord::Migration::CompatibilityBehavior
  end
end
