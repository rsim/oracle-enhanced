# frozen_string_literal: true

require "active_record/connection_adapters/oracle_enhanced/database_tasks"
require "active_support/testing/stream"
require "stringio"
require "tempfile"

describe "Oracle Enhanced adapter database tasks" do
  include SchemaSpecHelper

  let(:config) { CONNECTION_PARAMS.with_indifferent_access }

  describe "check_current_protected_environment!" do
    before do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      ActiveRecord::Base.connection_pool.schema_migration.create_table
    end

    after do
      ActiveRecord::Base.connection_pool.schema_migration.drop_table
    end

    it "is dispatched from ActiveRecord::Tasks::DatabaseTasks#check_protected_environments!" do
      original_configurations = ActiveRecord::Base.configurations
      ActiveRecord::Base.configurations = {
        "test" => CONNECTION_PARAMS.transform_keys(&:to_s)
      }
      expect {
        ActiveRecord::Tasks::DatabaseTasks.check_protected_environments!("test")
      }.not_to raise_error
    ensure
      ActiveRecord::Base.configurations = original_configurations
    end
  end

  describe "create" do
    let(:new_user_config) { config.merge(username: "oracle_enhanced_test_user") }
    before do
      fake_terminal(SYSTEM_CONNECTION_PARAMS[:password]) do
        ActiveRecord::Tasks::DatabaseTasks.create(new_user_config)
      end
    end

    it "creates user" do
      query = "SELECT COUNT(*) FROM dba_users WHERE UPPER(username) = '#{new_user_config[:username].upcase}'"
      expect(ActiveRecord::Base.lease_connection.select_value(query)).to eq(1)
    end
    it "grants permissions defined by OracleEnhancedAdapter.persmissions" do
      query = "SELECT COUNT(*) FROM DBA_SYS_PRIVS WHERE GRANTEE = '#{new_user_config[:username].upcase}'"
      permissions_count = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions.size
      expect(ActiveRecord::Base.lease_connection.select_value(query)).to eq(permissions_count)
    end
    after do
      ActiveRecord::Base.lease_connection.execute("DROP USER #{new_user_config[:username]}")
    end

    def fake_terminal(input)
      $stdin = StringIO.new
      $stdout = StringIO.new
      $stdin.puts(input)
      $stdin.rewind
      yield
    ensure
      $stdin = STDIN
      $stdout = STDOUT
    end
  end

  describe "create input validation" do
    around do |example|
      original_stderr, $stderr = $stderr, StringIO.new
      example.run
    ensure
      $stderr = original_stderr
    end

    it "raises ArgumentError before touching the database when :username is not an Oracle identifier" do
      invalid_config = config.merge(username: "oracle;DROP USER system;--")
      expect(ActiveRecord::Base).not_to receive(:establish_connection)
      expect {
        ActiveRecord::Tasks::DatabaseTasks.create(invalid_config)
      }.to raise_error(ArgumentError, /Invalid Oracle identifier for :username/)
    end

    it "raises ArgumentError before touching the database when OracleEnhancedAdapter.permissions contains a statement separator" do
      original_permissions = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions =
        ["create session; DROP USER system;--"]
      expect(ActiveRecord::Base).not_to receive(:establish_connection)
      expect {
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      }.to raise_error(ArgumentError, /Invalid Oracle privilege in OracleEnhancedAdapter.permissions/)
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions = original_permissions
    end

    it "raises ArgumentError before touching the database when OracleEnhancedAdapter.permissions contains a newline" do
      original_permissions = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions = ["create\nsession"]
      expect(ActiveRecord::Base).not_to receive(:establish_connection)
      expect {
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      }.to raise_error(ArgumentError, /Invalid Oracle privilege in OracleEnhancedAdapter.permissions/)
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions = original_permissions
    end
  end

  describe "create password quoting" do
    include ActiveSupport::Testing::Stream

    let(:captured_sqls) { [] }
    let(:fake_connection) do
      double("connection").tap do |c|
        allow(c).to receive(:execute) { |sql| captured_sqls << sql }
      end
    end

    before do
      allow(ActiveRecord::Base).to receive(:establish_connection)
      allow(ActiveRecord::Base).to receive(:lease_connection).and_return(fake_connection)
      ENV["ORACLE_SYSTEM_PASSWORD"] = "dummy"
    end

    after { ENV.delete("ORACLE_SYSTEM_PASSWORD") }

    it "wraps :password as a double-quoted literal with embedded double quotes doubled" do
      quietly do
        ActiveRecord::Tasks::DatabaseTasks.create(
          config.merge(username: "oracle_enhanced_test_user", password: %{p"w})
        )
      end
      create_sql = captured_sqls.first
      expect(create_sql).to eq(%{CREATE USER oracle_enhanced_test_user IDENTIFIED BY "p""w"})
    end
  end

  describe "create with ORACLE_SYSTEM_USER" do
    include ActiveSupport::Testing::Stream

    let(:captured_connect_config) { {} }
    let(:fake_connection) do
      double("connection").tap { |c| allow(c).to receive(:execute) }
    end

    before do
      allow(ActiveRecord::Base).to receive(:establish_connection) do |cfg|
        captured_connect_config.replace(cfg)
      end
      allow(ActiveRecord::Base).to receive(:lease_connection).and_return(fake_connection)
      ENV["ORACLE_SYSTEM_PASSWORD"] = "dummy"
    end

    after do
      ENV.delete("ORACLE_SYSTEM_PASSWORD")
      ENV.delete("ORACLE_SYSTEM_USER")
    end

    it "defaults to SYSTEM when ORACLE_SYSTEM_USER is unset" do
      quietly do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(captured_connect_config[:username]).to eq("SYSTEM")
    end

    it "uses the value of ORACLE_SYSTEM_USER when set (e.g. ADMIN on Oracle Cloud Autonomous Database)" do
      ENV["ORACLE_SYSTEM_USER"] = "ADMIN"
      quietly do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(captured_connect_config[:username]).to eq("ADMIN")
    end

    it "falls back to SYSTEM when ORACLE_SYSTEM_USER is set but empty" do
      ENV["ORACLE_SYSTEM_USER"] = ""
      quietly do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(captured_connect_config[:username]).to eq("SYSTEM")
    end

    it "falls back to SYSTEM when ORACLE_SYSTEM_USER is whitespace-only" do
      ENV["ORACLE_SYSTEM_USER"] = "   "
      quietly do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(captured_connect_config[:username]).to eq("SYSTEM")
    end

    it "raises ArgumentError before touching the database when ORACLE_SYSTEM_USER is not an Oracle identifier" do
      ENV["ORACLE_SYSTEM_USER"] = "oracle;DROP USER system;--"
      quietly do
        expect {
          ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
        }.to raise_error(ArgumentError, /Invalid Oracle identifier for ORACLE_SYSTEM_USER/)
      end
      expect(captured_connect_config).to be_empty
    end

    it "keeps the original 'SYSTEM password' prompt wording when ORACLE_SYSTEM_USER is unset" do
      ENV.delete("ORACLE_SYSTEM_PASSWORD")
      original_stdin = $stdin
      $stdin = StringIO.new("pwd\n")
      output = capture(:stdout) do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(output).to include("Please provide the SYSTEM password")
    ensure
      $stdin = original_stdin
    end

    it "names the override user in the prompt when ORACLE_SYSTEM_USER is set and ORACLE_SYSTEM_PASSWORD is unset" do
      ENV.delete("ORACLE_SYSTEM_PASSWORD")
      ENV["ORACLE_SYSTEM_USER"] = "ADMIN"
      original_stdin = $stdin
      $stdin = StringIO.new("pwd\n")
      output = capture(:stdout) do
        ActiveRecord::Tasks::DatabaseTasks.create(config.merge(username: "oracle_enhanced_test_user"))
      end
      expect(output).to include("Please provide the ADMIN password")
    ensure
      $stdin = original_stdin
    end
  end

  context "with test table" do
    before(:all) do
      $stdout, @original_stdout = StringIO.new, $stdout
      $stderr, @original_stderr = StringIO.new, $stderr
    end

    after(:all) do
      $stdout, $stderr = @original_stdout, @original_stderr
    end

    before do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :name, limit: 20
        end
      end
    end

    describe "drop" do
      before { ActiveRecord::Tasks::DatabaseTasks.drop(config) }

      it "drops all tables" do
        expect(ActiveRecord::Base.lease_connection.table_exists?(:test_posts)).to be_falsey
      end
    end

    describe "purge" do
      before { ActiveRecord::Tasks::DatabaseTasks.purge(config) }

      it "drops all tables" do
        expect(ActiveRecord::Base.lease_connection.table_exists?(:test_posts)).to be_falsey
        expect(ActiveRecord::Base.lease_connection.select_value("SELECT COUNT(*) FROM RECYCLEBIN")).to eq(0)
      end
    end

    describe "structure" do
      let(:temp_file) { Tempfile.create(["oracle_enhanced", ".sql"]).path }
      before do
        ActiveRecord::Base.connection_pool.schema_migration.create_table
        ActiveRecord::Base.lease_connection.execute "INSERT INTO schema_migrations (version) VALUES ('20150101010000')"
      end

      describe "structure_dump" do
        before { ActiveRecord::Tasks::DatabaseTasks.structure_dump(config, temp_file) }

        it "dumps the database structure to a file without the schema information" do
          contents = File.read(temp_file)
          expect(contents).to include('CREATE TABLE "TEST_POSTS"')
          expect(contents).not_to include("INSERT INTO schema_migrations")
        end
      end

      describe "structure_load" do
        before do
          ActiveRecord::Tasks::DatabaseTasks.structure_dump(config, temp_file)
          ActiveRecord::Tasks::DatabaseTasks.drop(config)
          ActiveRecord::Tasks::DatabaseTasks.structure_load(config, temp_file)
        end

        it "loads the database structure from a file" do
          expect(ActiveRecord::Base.lease_connection.table_exists?(:test_posts)).to be_truthy
        end
      end

      after do
        File.unlink(temp_file)
        ActiveRecord::Base.connection_pool.schema_migration.drop_table
      end
    end

    describe "structure_dump with db_stored_code" do
      let(:temp_file) { Tempfile.create(["oracle_enhanced", ".sql"]).path }
      let(:stored_code_config) { config.merge(structure_dump: "db_stored_code") }

      after { File.unlink(temp_file) if File.exist?(temp_file) }

      it "opens both writes with UTF-8 encoding" do
        target = temp_file
        opened = []
        allow(File).to receive(:open).and_wrap_original do |original, path, mode, *args, &block|
          opened << mode if path == target
          original.call(path, mode, *args, &block)
        end
        ActiveRecord::Tasks::DatabaseTasks.structure_dump(stored_code_config, target)
        expect(opened).to eq(["w:utf-8", "a:utf-8"])
      end
    end

    after do
      schema_define do
        drop_table :test_posts, if_exists: true
      end
    end
  end
end
