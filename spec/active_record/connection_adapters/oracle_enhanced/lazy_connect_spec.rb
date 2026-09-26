# frozen_string_literal: true

# rails/rails#44591 made adapters connect lazily: constructing an adapter
# does not open a connection, the first query (or #connect! / #verify!) does.
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
    expect { @adapter.connect! }.to raise_error(StandardError) { |error| expect(error).not_to be_a(NoMethodError) }
    expect(@adapter).not_to be_connected
  end

  it "resolves the Arel visitor from the server version on first use" do
    @adapter = adapter_class.new(CONNECTION_PARAMS)
    expected = @adapter.database_version >= "12" ? Arel::Visitors::Oracle12 : Arel::Visitors::Oracle
    expect(@adapter.visitor).to be_a(expected)
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
