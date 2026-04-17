# frozen_string_literal: true

#
# Tests for Rails multiple database support with oracle_enhanced.
# Adapted from rails/rails activerecord/test/cases/multiple_db_test.rb
#
# Pattern: abstract base class with establish_connection — the programmatic
# equivalent of connects_to — to connect models to a second Oracle schema.

describe "OracleEnhancedAdapter multiple database support" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)

    # Abstract base class for the remote schema. Defined before any tables are
    # created so the remote table can be built via its own connection without
    # rebinding ActiveRecord::Base.
    class ::MultiDbRemoteBase < ActiveRecord::Base
      self.abstract_class = true
      establish_connection REMOTE_CONNECTION_PARAMS
    end

    ActiveRecord::Base.connection.create_table :multi_db_primary_employees, force: true do |t|
      t.string :name, limit: 50
    end

    MultiDbRemoteBase.connection.create_table :multi_db_remote_employees, force: true do |t|
      t.string :name, limit: 50
    end

    class ::MultiDbPrimaryEmployee < ActiveRecord::Base
      self.table_name = "multi_db_primary_employees"
    end

    class ::MultiDbRemoteEmployee < MultiDbRemoteBase
      self.table_name = "multi_db_remote_employees"
    end

    # A second model inheriting from the same abstract base to test connection sharing
    class ::MultiDbRemoteEmployee2 < MultiDbRemoteBase
      self.table_name = "multi_db_remote_employees"
    end

    MultiDbPrimaryEmployee.create!(id: 1, name: "Primary Alice")
    MultiDbPrimaryEmployee.create!(id: 2, name: "Primary Bob")
    MultiDbRemoteEmployee.create!(id: 1, name: "Remote Alice")
    MultiDbRemoteEmployee.create!(id: 2, name: "Remote Bob")
  end

  after(:all) do
    if Object.const_defined?(:MultiDbRemoteBase)
      begin
        MultiDbRemoteBase.connection.drop_table :multi_db_remote_employees, if_exists: true
      ensure
        MultiDbRemoteBase.remove_connection
      end
    end
  ensure
    begin
      ActiveRecord::Base.connection.drop_table :multi_db_primary_employees, if_exists: true
    ensure
      %w[MultiDbPrimaryEmployee MultiDbRemoteEmployee MultiDbRemoteEmployee2 MultiDbRemoteBase].each do |name|
        Object.send(:remove_const, name) if Object.const_defined?(name)
      end
      ActiveRecord::Base.clear_cache!
    end
  end

  # Adapted from test_connected
  it "both connections are active" do
    expect(MultiDbPrimaryEmployee.lease_connection).not_to be_nil
    expect(MultiDbRemoteEmployee.lease_connection).not_to be_nil
  end

  # Adapted from test_proper_connection
  it "primary and remote models use different connections" do
    expect(MultiDbPrimaryEmployee.lease_connection).not_to eq(MultiDbRemoteEmployee.lease_connection)
    expect(MultiDbPrimaryEmployee.lease_connection).to eq(ActiveRecord::Base.lease_connection)
  end

  # Adapted from test_connection — subclass shares parent's connection
  it "two models on the same abstract base share the same connection" do
    expect(MultiDbRemoteEmployee.lease_connection).to eq(MultiDbRemoteEmployee2.lease_connection)
    expect(MultiDbRemoteEmployee.lease_connection).not_to eq(MultiDbPrimaryEmployee.lease_connection)
  end

  # Adapted from test_find
  it "find works independently on each connection" do
    p1 = MultiDbPrimaryEmployee.find(1)
    expect(p1.name).to eq("Primary Alice")

    p2 = MultiDbPrimaryEmployee.find(2)
    expect(p2.name).to eq("Primary Bob")

    r1 = MultiDbRemoteEmployee.find(1)
    expect(r1.name).to eq("Remote Alice")

    r2 = MultiDbRemoteEmployee.find(2)
    expect(r2.name).to eq("Remote Bob")
  end

  # Adapted from test_count_on_custom_connection
  it "count works on the remote connection" do
    expect(MultiDbRemoteEmployee.count).to eq(2)
    expect(MultiDbPrimaryEmployee.count).to eq(2)
  end

  # Adapted from test_transactions_across_databases
  # The raised RuntimeError propagates out of both transaction blocks, so each
  # connection rolls back its own transaction on its own — demonstrating that
  # there is no shared coordinator between the two connections' transactions.
  it "transactions are independent per connection" do
    p1 = MultiDbPrimaryEmployee.find(1)
    r1 = MultiDbRemoteEmployee.find(1)

    begin
      MultiDbPrimaryEmployee.transaction do
        MultiDbRemoteEmployee.transaction do
          p1.name = "Typo"
          r1.name = "Typo"
          p1.save!
          r1.save!
          raise RuntimeError, "rollback"
        end
      end
    rescue RuntimeError
      # caught
    end

    # Each model's transaction rolled back independently
    expect(MultiDbPrimaryEmployee.find(1).name).to eq("Primary Alice")
    expect(MultiDbRemoteEmployee.find(1).name).to eq("Remote Alice")
  end

  # Adapted from base_prevent_writes_test.rb — read/write split via while_preventing_writes

  # Adapted from test "creating a record raises if preventing writes"
  it "raises ReadOnlyError on INSERT inside while_preventing_writes" do
    expect {
      ActiveRecord::Base.while_preventing_writes do
        MultiDbPrimaryEmployee.create!(name: "Tempbird")
      end
    }.to raise_error(ActiveRecord::ReadOnlyError, /Write query attempted while in readonly mode: INSERT/)
  end

  # Adapted from test "updating a record raises if preventing writes"
  it "raises ReadOnlyError on UPDATE inside while_preventing_writes" do
    p1 = MultiDbPrimaryEmployee.find(1)
    expect {
      ActiveRecord::Base.while_preventing_writes do
        p1.update!(name: "Changed")
      end
    }.to raise_error(ActiveRecord::ReadOnlyError, /Write query attempted while in readonly mode: UPDATE/)
  end

  # Adapted from test "deleting a record raises if preventing writes"
  it "raises ReadOnlyError on DELETE inside while_preventing_writes" do
    p1 = MultiDbPrimaryEmployee.find(1)
    expect {
      ActiveRecord::Base.while_preventing_writes do
        p1.destroy!
      end
    }.to raise_error(ActiveRecord::ReadOnlyError, /Write query attempted while in readonly mode: DELETE/)
  end

  # Adapted from test "selecting a record does not raise if preventing writes"
  it "does not raise on SELECT inside while_preventing_writes" do
    ActiveRecord::Base.while_preventing_writes do
      expect(MultiDbPrimaryEmployee.where(name: "Primary Alice").first).not_to be_nil
    end
  end

  # Adapted from test "current_preventing_writes"
  it "current_preventing_writes returns true inside while_preventing_writes" do
    ActiveRecord::Base.while_preventing_writes do
      expect(ActiveRecord::Base.current_preventing_writes).to be true
    end
  end

  # Adapted from test "preventing writes applies to all connections in block"
  it "while_preventing_writes raises on the remote connection too" do
    expect {
      ActiveRecord::Base.while_preventing_writes do
        MultiDbRemoteEmployee.create!(name: "Tempbird")
      end
    }.to raise_error(ActiveRecord::ReadOnlyError, /Write query attempted while in readonly mode: INSERT/)
  end

  # Adapted from test_swapping_the_connection
  it "connection_specification_name can be swapped to point to a different pool" do
    original = MultiDbRemoteEmployee.connection_specification_name
    MultiDbRemoteEmployee.connection_specification_name = "ActiveRecord::Base"
    expect(MultiDbRemoteEmployee.lease_connection).to eq(ActiveRecord::Base.lease_connection)
  ensure
    MultiDbRemoteEmployee.connection_specification_name = original
  end

  # Adapted from test_exception_contains_connection_pool
  it "StatementInvalid error references the correct connection pool" do
    error = nil
    begin
      MultiDbRemoteEmployee.where(nonexistent_column: "x").first!
    rescue ActiveRecord::StatementInvalid => e
      error = e
    end
    expect(error).not_to be_nil
    expect(error.connection_pool).to eq(MultiDbRemoteEmployee.lease_connection.pool)
  end
end
