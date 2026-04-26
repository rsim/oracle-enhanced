# frozen_string_literal: true

#
# Confirms that the two Oracle schemas (CONNECTION_PARAMS and
# REMOTE_CONNECTION_PARAMS) are isolated from each other: even when using
# an explicit schema prefix, a cross-schema SELECT raises ORA-00942 unless
# a privilege has been explicitly granted.
#
# This holds regardless of the underlying topology — same PDB, separate
# PDBs, or entirely separate databases.
#

describe "Oracle schema isolation between primary and remote connections" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)

    # Abstract base for the remote schema, so the remote table is created via
    # its own connection and ActiveRecord::Base never has to be rebound.
    class ::SchemaIsolationRemoteBase < ActiveRecord::Base
      self.abstract_class = true
      establish_connection REMOTE_CONNECTION_PARAMS
    end

    ActiveRecord::Base.lease_connection.create_table :schema_isolation_primary, force: true do |t|
      t.string :name, limit: 50
    end

    SchemaIsolationRemoteBase.lease_connection.create_table :schema_isolation_remote, force: true do |t|
      t.string :name, limit: 50
    end
  end

  after(:all) do
    if Object.const_defined?(:SchemaIsolationRemoteBase)
      begin
        SchemaIsolationRemoteBase.lease_connection.drop_table :schema_isolation_remote, if_exists: true
      ensure
        begin
          SchemaIsolationRemoteBase.remove_connection
        ensure
          Object.send(:remove_const, :SchemaIsolationRemoteBase)
        end
      end
    end
  ensure
    begin
      ActiveRecord::Base.lease_connection.drop_table :schema_isolation_primary, if_exists: true
    ensure
      ActiveRecord::Base.clear_cache!
    end
  end

  # ORA-00942: table or view does not exist
  # Oracle returns this error for both "no such table" and "no SELECT privilege",
  # intentionally not distinguishing between the two.
  it "primary schema cannot directly access a table owned by the remote schema" do
    expect {
      ActiveRecord::Base.lease_connection.execute("SELECT * FROM #{DATABASE_REMOTE_USER}.schema_isolation_remote")
    }.to raise_error(ActiveRecord::StatementInvalid, /ORA-00942/)
  end

  it "remote schema cannot directly access a table owned by the primary schema" do
    expect {
      SchemaIsolationRemoteBase.lease_connection.execute("SELECT * FROM #{DATABASE_USER}.schema_isolation_primary")
    }.to raise_error(ActiveRecord::StatementInvalid, /ORA-00942/)
  end
end
