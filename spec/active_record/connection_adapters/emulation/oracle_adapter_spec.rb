# frozen_string_literal: true

describe "OracleEnhancedAdapter emulate OracleAdapter" do
  after(:all) do
    # Restore the default connection in case the example below replaced it.
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  it "should be an OracleAdapter" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(adapter: "oracle"))
    expect(ActiveRecord::Base.lease_connection).not_to be_nil
    expect(ActiveRecord::Base.lease_connection).to be_a(ActiveRecord::ConnectionAdapters::OracleAdapter)
  end
end
