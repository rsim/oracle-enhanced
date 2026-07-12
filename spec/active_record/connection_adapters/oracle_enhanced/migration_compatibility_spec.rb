# frozen_string_literal: true

RSpec.describe "OracleEnhanced::CompatibilityBehavior resolution" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  def oracle_behavior
    ActiveRecord::ConnectionAdapters::OracleEnhanced::CompatibilityBehavior
  end

  it "resolves Migration[8.2] to V8_2" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.2])).to eq oracle_behavior::V8_2
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
end
