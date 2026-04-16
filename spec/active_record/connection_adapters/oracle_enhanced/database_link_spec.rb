# frozen_string_literal: true

describe "OracleEnhancedAdapter database link" do
  before(:all) do
    # Create a table in oracle_enhanced_remote schema by connecting as that user
    ActiveRecord::Base.establish_connection(REMOTE_CONNECTION_PARAMS)
    ActiveRecord::Base.connection.create_table :remote_employees, force: true do |t|
      t.string :name, limit: 50
    end
    ActiveRecord::Base.connection.execute("INSERT INTO remote_employees (id, name) VALUES (1, 'Alice')")

    # Create a database link from oracle_enhanced to oracle_enhanced_remote.
    # Drop first so the spec is safe to re-run if a previous run crashed before teardown.
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    begin
      @conn.execute("DROP DATABASE LINK oracle_enhanced_remote_link")
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.message.include?("ORA-02024")
    end
    @conn.execute(<<~SQL)
      CREATE DATABASE LINK oracle_enhanced_remote_link
        CONNECT TO #{DATABASE_REMOTE_USER} IDENTIFIED BY #{DATABASE_REMOTE_PASSWORD}
        USING '#{DATABASE_HOST}:#{DATABASE_PORT}/#{DATABASE_NAME}'
    SQL

    class ::RemoteEmployee < ActiveRecord::Base
      self.table_name = "remote_employees@oracle_enhanced_remote_link"
    end
  end

  after(:all) do
    Object.send(:remove_const, "RemoteEmployee") if defined?(::RemoteEmployee)
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    begin
      ActiveRecord::Base.connection.execute("DROP DATABASE LINK oracle_enhanced_remote_link")
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.message.include?("ORA-02024")
    end
    ActiveRecord::Base.establish_connection(REMOTE_CONNECTION_PARAMS)
    ActiveRecord::Base.connection.drop_table :remote_employees, if_exists: true
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  it "reads records from a remote table via a database link" do
    employees = RemoteEmployee.all.to_a
    expect(employees.size).to eq(1)
    expect(employees.first.name).to eq("Alice")
  end

  it "finds a record by primary key via a database link" do
    employee = RemoteEmployee.find(1)
    expect(employee.name).to eq("Alice")
  end
end
