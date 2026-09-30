# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter lazy connection" do
  let(:adapter_class) { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  after(:each) do
    @adapter&.disconnect!
  end

  it "does not connect when the adapter is instantiated" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    expect(@adapter).not_to be_connected
    expect(@adapter).not_to be_active
  end

  it "connects and configures the session on the first query" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    expect(@adapter.select_value("SELECT 1 FROM dual")).to eq(1)
    expect(@adapter).to be_connected
    expect(@adapter.select_value("SELECT value FROM nls_session_parameters WHERE parameter = 'NLS_DATE_FORMAT'")).to eq("YYYY-MM-DD HH24:MI:SS")
  end

  it "does not raise on instantiation with bad credentials, only when connecting" do
    @adapter = adapter_class.new(CONNECTION_PARAMS.merge(password: "#{CONNECTION_PARAMS[:password]}_wrong"))
    expect(@adapter).not_to be_connected
    expect { @adapter.connect! }.to raise_error(ActiveRecord::DatabaseConnectionError)
    expect(@adapter).not_to be_connected
  end

  it "does not connect when a connection is checked out of the pool" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(password: "#{CONNECTION_PARAMS[:password]}_wrong"))
    conn = nil
    expect { conn = ActiveRecord::Base.lease_connection }.not_to raise_error
    expect(conn).not_to be_connected
    expect { conn.select_value("SELECT 1 FROM dual") }.to raise_error(ActiveRecord::DatabaseConnectionError) { |error|
      expect(error.connection_pool).to equal(ActiveRecord::Base.connection_pool)
    }
  ensure
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  it "builds the Arel visitor without connecting" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    expect(@adapter.visitor).not_to be_nil
    expect(@adapter).not_to be_connected
  end

  it "allows disconnect! before the first connection" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    expect { @adapter.disconnect! }.not_to raise_error
    expect(@adapter).not_to be_connected
  end

  it "reconnects on the next query after disconnect!" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    @adapter.connect!
    @adapter.disconnect!
    expect(@adapter).not_to be_connected
    expect(@adapter.select_value("SELECT 1 FROM dual")).to eq(1)
    expect(@adapter).to be_connected
  end
end
