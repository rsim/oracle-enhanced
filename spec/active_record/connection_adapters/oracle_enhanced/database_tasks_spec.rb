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
      expect(ActiveRecord::Base.connection.select_value(query)).to eq(1)
    end
    it "grants permissions defined by OracleEnhancedAdapter.persmissions" do
      query = "SELECT COUNT(*) FROM DBA_SYS_PRIVS WHERE GRANTEE = '#{new_user_config[:username].upcase}'"
      permissions_count = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.permissions.size
      expect(ActiveRecord::Base.connection.select_value(query)).to eq(permissions_count)
    end
    after do
      ActiveRecord::Base.connection.execute("DROP USER #{new_user_config[:username]}")
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
        expect(ActiveRecord::Base.connection.table_exists?(:test_posts)).to be_falsey
      end
    end

    describe "purge" do
      before { ActiveRecord::Tasks::DatabaseTasks.purge(config) }

      it "drops all tables" do
        expect(ActiveRecord::Base.connection.table_exists?(:test_posts)).to be_falsey
        expect(ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM RECYCLEBIN")).to eq(0)
      end
    end

    describe "structure" do
      let(:temp_file) { Tempfile.create(["oracle_enhanced", ".sql"]).path }
      before do
        ActiveRecord::Base.connection_pool.schema_migration.create_table
        ActiveRecord::Base.connection.execute "INSERT INTO schema_migrations (version) VALUES ('20150101010000')"
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
          expect(ActiveRecord::Base.connection.table_exists?(:test_posts)).to be_truthy
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
