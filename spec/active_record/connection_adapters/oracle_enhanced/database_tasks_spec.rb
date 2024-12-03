# frozen_string_literal: true

require "active_record/connection_adapters/oracle_enhanced/database_tasks"
require "stringio"
require "tempfile"

describe "Oracle Enhanced adapter database tasks" do
  include SchemaSpecHelper

  let(:config) { CONNECTION_PARAMS.with_indifferent_access }

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

    after do
      schema_define do
        drop_table :test_posts, if_exists: true
      end
    end
  end
end
