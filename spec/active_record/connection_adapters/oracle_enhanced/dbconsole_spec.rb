# frozen_string_literal: true

describe "Oracle Enhanced adapter dbconsole" do
  subject { ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter }

  it "uses sqlplus to connect to database" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "user@db")

    config = make_db_config(adapter: "oracle", database: "db", username: "user", password: "secret")

    subject.dbconsole(config)
  end

  it "uses sqlplus with password when specified" do
    expect(subject).to receive(:find_cmd_and_exec).with("sqlplus", "user/secret@db")

    config = make_db_config(adapter: "oracle", database: "db", username: "user", password: "secret")

    subject.dbconsole(config, include_password: true)
  end

  private

  def make_db_config(config)
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", config)
  end
end
