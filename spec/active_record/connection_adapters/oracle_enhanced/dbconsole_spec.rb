# frozen_string_literal: true

describe "Oracle Enhanced adapter dbconsole" do
  subject { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  it "uses sqlplus with user@db when password is not requested" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "user@db")

    config = make_db_config(adapter: "oracle_enhanced", database: "db", username: "user", password: "secret")

    subject.dbconsole(config)
  end

  it "uses sqlplus with user/password@db when include_password is true" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "user/secret@db")

    config = make_db_config(adapter: "oracle_enhanced", database: "db", username: "user", password: "secret")

    subject.dbconsole(config, include_password: true)
  end

  it "omits @database when no database is configured" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "user")

    config = make_db_config(adapter: "oracle_enhanced", username: "user")

    subject.dbconsole(config)
  end

  it "passes an empty logon string when no username is configured" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "")

    config = make_db_config(adapter: "oracle_enhanced", database: "db")

    subject.dbconsole(config)
  end

  it "is inherited by the emulated OracleAdapter" do
    require "active_record/connection_adapters/emulation/oracle_adapter"
    expect(ActiveRecord::ConnectionAdapters::OracleAdapter).to receive(:find_cmd_and_exec).with("sqlplus", "user@db")

    config = make_db_config(adapter: "oracle", database: "db", username: "user", password: "secret")

    ActiveRecord::ConnectionAdapters::OracleAdapter.dbconsole(config)
  end

  it "respects ActiveRecord.database_cli[:oracle] when set" do
    original = ActiveRecord.database_cli[:oracle]
    ActiveRecord.database_cli[:oracle] = "sqlcl"
    expect(subject).to receive(:find_cmd_and_exec).with("sqlcl", "user@db")

    config = make_db_config(adapter: "oracle_enhanced", database: "db", username: "user")

    subject.dbconsole(config)
  ensure
    ActiveRecord.database_cli[:oracle] = original
  end

  private
    def make_db_config(config)
      ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config)
    end
end
