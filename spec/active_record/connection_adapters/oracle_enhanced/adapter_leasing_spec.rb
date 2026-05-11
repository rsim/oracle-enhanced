# frozen_string_literal: true

require "spec_helper"

# Ported from activerecord/test/cases/connection_adapters/adapter_leasing_test.rb.
RSpec.describe "OracleEnhancedAdapter leasing" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.new(CONNECTION_PARAMS)
  end

  it "starts out not in use and is in use after lease" do
    expect(@adapter.in_use?).to be_falsey
    @adapter.lease
    expect(@adapter).to be_in_use
  end

  it "raises ActiveRecordError when leased twice without an intervening expire" do
    @adapter.lease
    expect { @adapter.lease }.to raise_error(ActiveRecord::ActiveRecordError)
  end

  it "clears in_use? after expire" do
    @adapter.lease
    expect(@adapter).to be_in_use
    @adapter.expire
    expect(@adapter.in_use?).to be_falsey
  end
end

RSpec.describe "OracleEnhancedAdapter#raw_connection" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
  end

  it "routes through AR core's with_raw_connection wrapper" do
    expect(@adapter).to receive(:with_raw_connection).and_call_original
    @adapter.raw_connection
  end

  it "returns the bare OCI8 / JDBC driver, not the OracleEnhanced::Connection wrapper" do
    raw = @adapter.raw_connection
    expect(raw).not_to be_a(ActiveRecord::ConnectionAdapters::OracleEnhanced::Connection)
  end

  it "disables lazy transactions for the rest of the checkout" do
    @adapter.raw_connection
    expect(@adapter.transaction_manager.lazy_transactions_enabled?).to be(false)
  end
end

RSpec.describe "OracleEnhancedAdapter#discard!" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
  end

  it "clears @raw_connection so the adapter reports as disconnected" do
    expect(@adapter.connected?).to be(true)
    @adapter.discard!
    expect(@adapter.connected?).to be(false)
  end
end

RSpec.describe "OracleEnhancedAdapter transaction state changes" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
  end

  describe "#begin_db_transaction" do
    after(:each) do
      @adapter.exec_rollback_db_transaction
    end

    it "routes through with_raw_connection with allow_retry: true, materialize_transactions: false" do
      allow(@adapter).to receive(:with_raw_connection).and_call_original
      @adapter.begin_db_transaction
      expect(@adapter).to have_received(:with_raw_connection)
        .with(allow_retry: true, materialize_transactions: false)
    end
  end

  describe "#commit_db_transaction" do
    before(:each) do
      @adapter.begin_db_transaction
    end

    it "routes through with_raw_connection with allow_retry: false, materialize_transactions: true" do
      allow(@adapter).to receive(:with_raw_connection).and_call_original
      @adapter.commit_db_transaction
      expect(@adapter).to have_received(:with_raw_connection)
        .with(allow_retry: false, materialize_transactions: true)
    end
  end

  describe "#exec_rollback_db_transaction" do
    before(:each) do
      @adapter.begin_db_transaction
    end

    it "routes through with_raw_connection with allow_retry: false, materialize_transactions: true" do
      allow(@adapter).to receive(:with_raw_connection).and_call_original
      @adapter.exec_rollback_db_transaction
      expect(@adapter).to have_received(:with_raw_connection)
        .with(allow_retry: false, materialize_transactions: true)
    end
  end
end

RSpec.describe "OracleEnhancedAdapter#_exec_insert" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
    @adapter.create_table(:test_allow_retry_inserts, force: true) do |t|
      t.string :name
    end
    @model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_allow_retry_inserts"
    end
  end

  after(:each) do
    @adapter.drop_table(:test_allow_retry_inserts, if_exists: true)
  end

  it "routes the INSERT cursor through with_raw_connection with allow_retry: true" do
    allow(@adapter).to receive(:with_raw_connection).and_call_original
    @model_class.create!(name: "x")
    expect(@adapter).to have_received(:with_raw_connection).with(allow_retry: true).at_least(:once)
  end
end

RSpec.describe "OracleEnhancedAdapter#resolve_data_source_name" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
    @adapter.create_table(:test_allow_retry_describe, force: true) { |t| t.string :name }
  end

  after(:each) do
    @adapter.drop_table(:test_allow_retry_describe, if_exists: true)
  end

  it "routes DBMS_UTILITY.NAME_RESOLVE through with_raw_connection with allow_retry: true" do
    allow(@adapter).to receive(:with_raw_connection).and_call_original
    @adapter.data_source_exists?(:test_allow_retry_describe)
    expect(@adapter).to have_received(:with_raw_connection).with(allow_retry: true).at_least(:once)
  end
end

RSpec.describe "OracleEnhancedAdapter#write_lobs" do
  before(:each) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @adapter = ActiveRecord::Base.lease_connection
    @adapter.create_table(:test_allow_retry_lobs, force: true) do |t|
      t.text :body
    end
    @old_prepared_statements = @adapter.prepared_statements
    @adapter.instance_variable_set(:@prepared_statements, false)
    @model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_allow_retry_lobs"
    end
    @model_class.create!(body: "x" * 5000)
  end

  after(:each) do
    @adapter.instance_variable_set(:@prepared_statements, @old_prepared_statements)
    @adapter.drop_table(:test_allow_retry_lobs, if_exists: true)
  end

  # The LOB locator from the preceding SELECT ... FOR UPDATE is tied to the
  # OCI session, so a reconnect-and-retry would either be a no-op (the
  # surrounding transaction is already dirty) or fail with ORA-22275 /
  # ORA-22920 on the new session. Pin the flag explicitly to false.
  it "routes the LOB write through with_raw_connection with allow_retry: false" do
    allow(@adapter).to receive(:with_raw_connection).and_call_original
    @model_class.last.update!(body: "y" * 5000)
    expect(@adapter).to have_received(:with_raw_connection).with(allow_retry: false).at_least(:once)
  end
end
