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
      t.integer :multi_db_remote_employee_id
    end

    MultiDbRemoteBase.connection.create_table :multi_db_remote_employees, force: true do |t|
      t.string :name, limit: 50
    end

    class ::MultiDbPrimaryEmployee < ActiveRecord::Base
      self.table_name = "multi_db_primary_employees"
      belongs_to :multi_db_remote_employee
    end

    class ::MultiDbRemoteEmployee < MultiDbRemoteBase
      self.table_name = "multi_db_remote_employees"
      has_many :multi_db_primary_employees, foreign_key: :multi_db_remote_employee_id
    end

    # A second model inheriting from the same abstract base to test connection sharing
    class ::MultiDbRemoteEmployee2 < MultiDbRemoteBase
      self.table_name = "multi_db_remote_employees"
    end

    MultiDbPrimaryEmployee.create!(id: 1, name: "Primary Alice", multi_db_remote_employee_id: 1)
    MultiDbPrimaryEmployee.create!(id: 2, name: "Primary Bob", multi_db_remote_employee_id: 2)
    MultiDbRemoteEmployee.create!(id: 1, name: "Remote Alice")
    MultiDbRemoteEmployee.create!(id: 2, name: "Remote Bob")
  end

  after(:all) do
    if Object.const_defined?(:MultiDbRemoteBase)
      MultiDbRemoteBase.connection.drop_table :multi_db_remote_employees, if_exists: true
      MultiDbRemoteBase.remove_connection
    end
    ActiveRecord::Base.connection.drop_table :multi_db_primary_employees, if_exists: true
    %w[MultiDbPrimaryEmployee MultiDbRemoteEmployee MultiDbRemoteEmployee2 MultiDbRemoteBase].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
    ActiveRecord::Base.clear_cache!
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

  # Adapted from test_transactions_across_databases.
  # Note: because the RuntimeError propagates out of both transaction blocks,
  # both connections roll back here. This matches the Rails original, but on
  # its own it cannot distinguish "each connection rolled back independently"
  # from "one rollback cascaded through a shared coordinator". The
  # "only the inner remote transaction is rolled back" spec below verifies the
  # independence property more directly.
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

  # Directly verifies transaction independence: rolling back the inner remote
  # transaction (via ActiveRecord::Rollback) must not roll back the outer
  # primary transaction, since the two connections are separate. If a shared
  # coordinator were linking them, the primary commit would also be lost and
  # this spec would fail.
  it "only the inner remote transaction is rolled back when the primary transaction commits" do
    p1 = MultiDbPrimaryEmployee.find(1)
    r1 = MultiDbRemoteEmployee.find(1)

    MultiDbPrimaryEmployee.transaction do
      p1.update!(name: "Primary Changed")
      MultiDbRemoteEmployee.transaction do
        r1.update!(name: "Remote Changed")
        raise ActiveRecord::Rollback
      end
    end

    expect(MultiDbPrimaryEmployee.find(1).name).to eq("Primary Changed")
    expect(MultiDbRemoteEmployee.find(1).name).to eq("Remote Alice")
  ensure
    MultiDbPrimaryEmployee.where(id: 1).update_all(name: "Primary Alice")
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

  # Adapted from test "an explain query does not raise if preventing writes"
  it "an EXPLAIN query does not raise inside while_preventing_writes" do
    ActiveRecord::Base.while_preventing_writes do
      expect { MultiDbPrimaryEmployee.where(name: "Primary Alice").explain.inspect }.not_to raise_error
    end
  end

  # Adapted from test "an empty transaction does not raise if preventing writes"
  it "an empty transaction does not raise inside while_preventing_writes" do
    expect {
      ActiveRecord::Base.while_preventing_writes do
        MultiDbPrimaryEmployee.transaction do
          ActiveRecord::Base.lease_connection.materialize_transactions
        end
      end
    }.not_to raise_error
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

  # Adapted from test_exception_contains_connection_pool.
  # ORA-00904 ("invalid identifier") is the specific error we expect here —
  # pinning the code ensures the test fails loudly if a different error
  # (connection failure, pool exhaustion, etc.) masquerades as success.
  it "StatementInvalid error references the correct connection pool" do
    error = nil
    begin
      MultiDbRemoteEmployee.where(nonexistent_column: "x").first!
    rescue ActiveRecord::StatementInvalid => e
      error = e
    end
    expect(error).not_to be_nil
    expect(error.message).to match(/ORA-00904/)
    expect(error.connection_pool).to eq(MultiDbRemoteEmployee.lease_connection.pool)
  end

  # Adapted from test_exception_contains_correct_pool.
  # ORA-00942 ("table or view does not exist") is the expected error for a
  # cross-schema SELECT without grants — pinning the code guards against
  # unrelated failures being accepted by the broader StatementInvalid rescue.
  it "StatementInvalid error from each connection references its own pool" do
    primary_conn = MultiDbPrimaryEmployee.lease_connection
    remote_conn = MultiDbRemoteEmployee.lease_connection
    expect(primary_conn).not_to eq(remote_conn)

    primary_error = nil
    begin
      primary_conn.execute("SELECT * FROM #{DATABASE_REMOTE_USER}.multi_db_remote_employees")
    rescue ActiveRecord::StatementInvalid => e
      primary_error = e
    end
    expect(primary_error).not_to be_nil
    expect(primary_error.message).to match(/ORA-00942/)
    expect(primary_error.connection_pool).to eq(primary_conn.pool)

    remote_error = nil
    begin
      remote_conn.execute("SELECT * FROM #{DATABASE_USER}.multi_db_primary_employees")
    rescue ActiveRecord::StatementInvalid => e
      remote_error = e
    end
    expect(remote_error).not_to be_nil
    expect(remote_error.message).to match(/ORA-00942/)
    expect(remote_error.connection_pool).to eq(remote_conn.pool)
  end

  # Adapted from test_associations
  it "associations work across connections" do
    r1 = MultiDbRemoteEmployee.find(1)
    expect(r1.multi_db_primary_employees.count).to eq(1)
    p1 = MultiDbPrimaryEmployee.find(1)
    expect(p1.multi_db_remote_employee.id).to eq(r1.id)

    r2 = MultiDbRemoteEmployee.find(2)
    expect(r2.multi_db_primary_employees.count).to eq(1)
    p2 = MultiDbPrimaryEmployee.find(2)
    expect(p2.multi_db_remote_employee.id).to eq(r2.id)
  end

  # Adapted from test_associations_should_work_when_model_has_no_connection
  it "associations work on a model whose connection is inherited from an abstract base" do
    expect { MultiDbRemoteEmployee.first.multi_db_primary_employees.first }.not_to raise_error
  end

  # Adapted from test_course_connection_should_survive_reloads
  it "connection survives model reload" do
    original = MultiDbRemoteEmployee
    expect(original.lease_connection).not_to be_nil
    Object.send(:remove_const, :MultiDbRemoteEmployee)
    class ::MultiDbRemoteEmployee < MultiDbRemoteBase
      self.table_name = "multi_db_remote_employees"
      has_many :multi_db_primary_employees, foreign_key: :multi_db_remote_employee_id
    end
    expect(MultiDbRemoteEmployee.lease_connection).not_to be_nil
  ensure
    Object.send(:remove_const, :MultiDbRemoteEmployee) if Object.const_defined?(:MultiDbRemoteEmployee)
    Object.const_set(:MultiDbRemoteEmployee, original) if original
  end
end
