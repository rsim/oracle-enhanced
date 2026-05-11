# frozen_string_literal: true

require "spec_helper"

# Ported from `activerecord/test/cases/transactions_test.rb` (Rails PR #32647).
# Verifies the `supports_lazy_transactions?` contract on Oracle:
#
# - An empty transaction is not materialized (no `autocommit = false` toggle
#   nor any `BEGIN`-equivalent fired).
# - A DML statement inside the transaction triggers materialization.
# - Savepoints / raising do not materialize on their own.
# - Accessing `raw_connection` materializes and disables lazy transactions
#   until the connection is checked back into the pool.
# - `materialize_transactions` can be called manually.
#
# Unlike MySQL/PG, Oracle does not emit a literal `BEGIN` statement —
# `begin_db_transaction` toggles the connection's autocommit flag. We
# therefore assert against `current_transaction.materialized?` directly
# rather than scanning SQL logs for `/BEGIN|COMMIT/i`.

RSpec.describe "OracleEnhancedAdapter lazy transactions" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    schema_define do
      drop_table :test_lazy_txn, if_exists: true
      create_table :test_lazy_txn, force: true do |t|
        t.string :name
      end
    end

    class ::TestLazyTxnRecord < ActiveRecord::Base
      self.table_name = "test_lazy_txn"
    end
  end

  after(:all) do
    Object.send(:remove_const, "TestLazyTxnRecord") if defined?(::TestLazyTxnRecord)
    schema_define do
      drop_table :test_lazy_txn, if_exists: true
    end
  end

  before(:each) do
    # `raw_connection` / `disable_lazy_transactions!` mutate per-checkout
    # state that the pool only resets on checkin. Specs in this file may
    # toggle that flag — return the connection to the pool and re-lease
    # so each example starts with lazy transactions enabled.
    ActiveRecord::Base.connection_pool.checkin(@conn)
    @conn = ActiveRecord::Base.lease_connection
    @conn.enable_lazy_transactions!
  end

  it "reports supports_lazy_transactions? as true" do
    expect(@conn.supports_lazy_transactions?).to be(true)
  end

  # Rails core: test_empty_transaction_is_not_materialized
  it "does not materialize an empty transaction" do
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
    end
  end

  # Rails core: test_unprepared_statement_materializes_transaction
  it "materializes the transaction when a query runs inside it" do
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
      TestLazyTxnRecord.where("1 = 1").to_a
      expect(@conn.current_transaction).to be_materialized
    end
  end

  # Rails core: test_savepoint_does_not_materialize_transaction
  it "does not materialize when only a nested savepoint runs" do
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) { }
      expect(@conn.current_transaction).not_to be_materialized
    end
  end

  # Rails core: test_raising_does_not_materialize_transaction
  it "does not materialize when the block raises before any query" do
    expect {
      ActiveRecord::Base.transaction do
        expect(@conn.current_transaction).not_to be_materialized
        raise "expected"
      end
    }.to raise_error("expected")
  end

  # Rails core: test_accessing_raw_connection_materializes_transaction
  it "materializes when raw_connection is accessed" do
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
      @conn.raw_connection
      expect(@conn.current_transaction).to be_materialized
    end
  end

  # Rails core: test_accessing_raw_connection_disables_lazy_transactions
  it "disables lazy transactions for the rest of the checkout after raw_connection access" do
    @conn.raw_connection
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).to be_materialized
    end
  end

  # Rails core: test_checking_in_connection_reenables_lazy_transactions
  it "re-enables lazy transactions when the connection is checked in to the pool" do
    connection = ActiveRecord::Base.connection_pool.checkout
    connection.raw_connection # disables lazy on this checkout
    ActiveRecord::Base.connection_pool.checkin(connection)

    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
    end
  end

  # Rails core: test_transactions_can_be_manually_materialized
  it "can be manually materialized via materialize_transactions" do
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
      @conn.materialize_transactions
      expect(@conn.current_transaction).to be_materialized
    end
  end

  # Oracle-specific addenda: the pre-DML `not_to be_materialized` is the
  # discriminator that fails when the flag flip is reverted; the post-DML
  # `materialized?` + `autocommit?` pair sanity-checks the OCI/JDBC
  # autocommit toggle in both directions.
  it "rolls back DML inside a lazy transaction" do
    before_count = TestLazyTxnRecord.count
    expect {
      ActiveRecord::Base.transaction do
        expect(@conn.current_transaction).not_to be_materialized
        TestLazyTxnRecord.create!(name: "rolled back")
        expect(@conn.current_transaction).to be_materialized
        expect(@conn.send(:_connection).autocommit?).to be(false)
        raise "abort"
      end
    }.to raise_error("abort")
    expect(TestLazyTxnRecord.count).to eq(before_count)
  end

  it "commits DML inside a lazy transaction" do
    before_count = TestLazyTxnRecord.count
    ActiveRecord::Base.transaction do
      expect(@conn.current_transaction).not_to be_materialized
      TestLazyTxnRecord.create!(name: "committed")
      expect(@conn.current_transaction).to be_materialized
      expect(@conn.send(:_connection).autocommit?).to be(false)
    end
    expect(TestLazyTxnRecord.count).to eq(before_count + 1)
  ensure
    TestLazyTxnRecord.delete_all
  end
end
