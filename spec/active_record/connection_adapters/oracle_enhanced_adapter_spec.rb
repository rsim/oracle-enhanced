# frozen_string_literal: true

describe "OracleEnhancedAdapter" do
  include LoggerSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  describe "cache table columns" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.string  :first_name, limit: 20
          t.string  :last_name, limit: 25
          if ActiveRecord::Base.connection.supports_virtual_columns?
            t.virtual :full_name, as: "(first_name || ' ' || last_name)"
          else
            t.string  :full_name, limit: 46
          end
          t.date    :hire_date
        end
      end
      schema_define do
        create_table :test_employees_without_pk, id: false, force: true do |t|
          t.string  :first_name, limit: 20
          t.string  :last_name, limit: 25
          t.date    :hire_date
        end
      end
      @column_names = ["id", "first_name", "last_name", "full_name", "hire_date"]
      @column_sql_types = ["NUMBER(38)", "VARCHAR2(20)", "VARCHAR2(25)", "VARCHAR2(46)", "DATE"]
      class ::TestEmployee < ActiveRecord::Base
      end
      # Another class using the same table
      class ::TestEmployee2 < ActiveRecord::Base
        self.table_name = "test_employees"
      end
    end

    after(:all) do
      @conn = ActiveRecord::Base.connection
      Object.send(:remove_const, "TestEmployee")
      Object.send(:remove_const, "TestEmployee2")
      @conn.drop_table :test_employees, if_exists: true
      @conn.drop_table :test_employees_without_pk, if_exists: true
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
      @conn = ActiveRecord::Base.connection
    end

    after(:each) do
      clear_logger
    end

    describe "without column caching" do

      it "should identify virtual columns as such" do
        skip "Not supported in this database version" unless @conn.supports_virtual_columns?
        te = TestEmployee.connection.columns("test_employees").detect(&:virtual?)
        expect(te.name).to eq("full_name")
      end

      it "should get columns from database at first time" do
        expect(TestEmployee.connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get columns from database at second time" do
        TestEmployee.connection.columns("test_employees")
        @logger.clear(:debug)
        expect(TestEmployee.connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should have correct sql types when 2 models are using the same table and AR query cache is enabled" do
        @conn.cache do
          expect(TestEmployee.columns.map(&:sql_type)).to eq(@column_sql_types)
          expect(TestEmployee2.columns.map(&:sql_type)).to eq(@column_sql_types)
        end
      end
    end
  end

  describe "access table over database link" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @db_link = "db_link"
      @sys_conn = ActiveRecord::Base.oracle_enhanced_connection(SYSTEM_CONNECTION_PARAMS)
      @sys_conn.drop_table :test_posts, if_exists: true
      @sys_conn.create_table :test_posts do |t|
        t.string      :title
        # cannot update LOBs over database link
        t.string      :body
        t.timestamps null: true
      end
      @db_link_username = SYSTEM_CONNECTION_PARAMS[:username]
      @db_link_password = SYSTEM_CONNECTION_PARAMS[:password]
      @db_link_database = SYSTEM_CONNECTION_PARAMS[:database]
      @conn.execute "DROP DATABASE LINK #{@db_link}" rescue nil
      @conn.execute "CREATE DATABASE LINK #{@db_link} CONNECT TO #{@db_link_username} IDENTIFIED BY \"#{@db_link_password}\" USING '#{@db_link_database}'"
      @conn.execute "CREATE OR REPLACE SYNONYM test_posts FOR test_posts@#{@db_link}"
      @conn.execute "CREATE OR REPLACE SYNONYM test_posts_seq FOR test_posts_seq@#{@db_link}"
      class ::TestPost < ActiveRecord::Base
      end
      TestPost.table_name = "test_posts"
    end

    after(:all) do
      @conn.execute "DROP SYNONYM test_posts"
      @conn.execute "DROP SYNONYM test_posts_seq"
      @conn.execute "DROP DATABASE LINK #{@db_link}" rescue nil
      @sys_conn.drop_table :test_posts, if_exists: true
      Object.send(:remove_const, "TestPost") rescue nil
      ActiveRecord::Base.clear_cache!
    end

    it "should verify database link" do
      @conn.select_value("select * from dual@#{@db_link}") == "X"
    end

    it "should get column names" do
      expect(TestPost.column_names).to eq(["id", "title", "body", "created_at", "updated_at"])
    end

    it "should create record" do
      p = TestPost.create(title: "Title", body: "Body")
      expect(p.id).not_to be_nil
      expect(TestPost.find(p.id)).not_to be_nil
    end

  end

  describe "session information" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    it "should get current database name" do
      # get database name if using //host:port/database connection string
      database_name = CONNECTION_PARAMS[:database].split("/").last
      expect(@conn.current_database.upcase).to eq(database_name.upcase)
    end

    it "should get current database session user" do
      expect(@conn.current_user.upcase).to eq(CONNECTION_PARAMS[:username].upcase)
    end
  end

  describe "temporary tables" do
    before(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:table] = "UNUSED"
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = "UNUSED"
      @conn = ActiveRecord::Base.connection
    end
    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces = {}
    end

    after(:each) do
      @conn.drop_table :foos, if_exists: true
    end
    it "should create ok" do
      @conn.create_table :foos, temporary: true, id: false do |t|
        t.integer :id
        t.text :bar
      end
    end
    it "should show up as temporary" do
      @conn.create_table :foos, temporary: true, id: false do |t|
        t.integer :id
      end
      expect(@conn.temporary_table?("foos")).to be_truthy
    end
  end

  describe "eager loading" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string      :title
        end
        create_table :test_comments do |t|
          t.integer     :test_post_id
          t.string      :description
        end
        add_index :test_comments, :test_post_id
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
      @ids = (1..1010).to_a
      TestPost.transaction do
        @ids.each do |id|
          TestPost.create!(id: id, title: "Title #{id}")
          TestComment.create!(test_post_id: id, description: "Description #{id}")
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      ActiveRecord::Base.clear_cache!
    end

    it "should load included association with more than 1000 records" do
      posts = TestPost.includes(:test_comments).to_a
      expect(posts.size).to eq(@ids.size)
    end

  end

  describe "with statement pool" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(statement_limit: 3))
      @conn = ActiveRecord::Base.connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
      @statements = @conn.instance_variable_get(:@statements)
    end

    before(:each) do
      @conn.clear_cache!
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should clear older cursors when statement limit is reached" do
      binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
      # free statement pool from dictionary selections  to ensure next selects will increase statement pool
      @statements.clear
      expect {
        4.times do |i|
          @conn.exec_query("SELECT * FROM test_posts WHERE #{i}=#{i} AND id = :id", "SQL", binds)
        end
      }.to change(@statements, :length).by(+3)
    end

    it "should cache UPDATE statements with bind variables" do
      expect {
        binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
        @conn.exec_update("UPDATE test_posts SET id = :id", "SQL", binds)
      }.to change(@statements, :length).by(+1)
    end

    it "should not cache UPDATE statements without bind variables" do
      expect {
        binds = []
        @conn.exec_update("UPDATE test_posts SET id = 1", "SQL", binds)
      }.not_to change(@statements, :length)
    end
  end

  describe "explain" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should explain query" do
      explain = TestPost.where(id: 1).explain
      expect(explain).to include("Cost")
      expect(explain).to include("INDEX UNIQUE SCAN")
    end

    it "should explain query with binds" do
      binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
      explain = TestPost.where(id: binds).explain
      expect(explain).to include("Cost")
      expect(explain).to include("INDEX UNIQUE SCAN").or include("TABLE ACCESS FULL")
    end
  end

  describe "using offset and limit" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.integer   :sort_order
          t.string    :first_name, limit: 20
          t.string    :last_name, limit: 20
          t.timestamps
        end
      end
      @employee = Class.new(ActiveRecord::Base) do
        self.table_name = :test_employees
      end
      i = 0
      @employee.create!(sort_order: i += 1, first_name: "Peter",   last_name: "Parker")
      @employee.create!(sort_order: i += 1, first_name: "Tony",    last_name: "Stark")
      @employee.create!(sort_order: i += 1, first_name: "Steven",  last_name: "Rogers")
      @employee.create!(sort_order: i += 1, first_name: "Bruce",   last_name: "Banner")
      @employee.create!(sort_order: i += 1, first_name: "Natasha", last_name: "Romanova")
    end

    after(:all) do
      @conn.drop_table :test_employees, if_exists: true
    end

    after(:each) do
      ActiveRecord::Base.clear_cache!
    end

    it "should return n records with limit(n)" do
      expect(@employee.limit(3).to_a.size).to be(3)
    end

    it "should return less than n records with limit(n) if there exist less than n records" do
      expect(@employee.limit(10).to_a.size).to be(5)
    end

    it "should return the records starting from offset n with offset(n)" do
      expect(@employee.order(:sort_order).first.first_name).to eq("Peter")
      expect(@employee.order(:sort_order).offset(0).first.first_name).to eq("Peter")
      expect(@employee.order(:sort_order).offset(1).first.first_name).to eq("Tony")
      expect(@employee.order(:sort_order).offset(4).first.first_name).to eq("Natasha")
    end
  end

  describe "valid_type?" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.string :first_name, limit: 20
        end
      end
    end

    after(:all) do
      @conn.drop_table :test_employees, if_exists: true
    end

    it "returns true when passed a valid type" do
      column = @conn.columns("test_employees").find { |col| col.name == "first_name" }
      expect(@conn.valid_type?(column.type)).to be true
    end

    it "returns false when passed an invalid type" do
      expect(@conn.valid_type?(:foobar)).to be false
    end
  end

  describe "serialized column" do
    before(:all) do
      schema_define do
        create_table :test_serialized_columns do |t|
          t.text :serialized
        end
      end
      class ::TestSerializedColumn < ActiveRecord::Base
        serialize :serialized, Array
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_serialized_columns
      end
      Object.send(:remove_const, "TestSerializedColumn")
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "should serialize" do
      new_value = "new_value"
      serialized_column = TestSerializedColumn.new

      expect(serialized_column.serialized).to eq([])
      serialized_column.serialized << new_value
      expect(serialized_column.serialized).to eq([new_value])
      serialized_column.save
      expect(serialized_column.save!).to eq(true)

      serialized_column.reload
      expect(serialized_column.serialized).to eq([new_value])
      serialized_column.serialized = []
      expect(serialized_column.save!).to eq(true)
    end
  end

  describe "quoting" do
    before(:all) do
      schema_define do
        create_table :test_logs, force: true do |t|
          t.timestamp :send_time
        end
      end
      class TestLog < ActiveRecord::Base
        validates_uniqueness_of :send_time
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_logs
      end
      Object.send(:remove_const, "TestLog")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should create records including Time"  do
      TestLog.create! send_time: Time.now + 1.seconds
      TestLog.create! send_time: Time.now + 2.seconds
      expect(TestLog.count).to eq 2
    end
  end

  describe "synonym_names" do
    before(:all) do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :comment
        end
        add_synonym :synonym_comments, :test_comments
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments
        remove_synonym :synonym_comments
      end
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "includes synonyms in data_source" do
      conn = ActiveRecord::Base.connection
      expect(conn).to be_data_source_exist("synonym_comments")
      expect(conn.data_sources).to include("synonym_comments")
    end
  end

  describe "dictionary selects with bind variables" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
    end

    before(:each) do
      @conn.clear_cache!
      set_logger
    end

    after(:each) do
      clear_logger
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should test table existence" do
      expect(@conn.table_exists?("TEST_POSTS")).to eq true
      expect(@conn.table_exists?("NOT_EXISTING")).to eq false
    end

    it "should return array from indexes with bind usage" do
      expect(@conn.indexes("TEST_POSTS").class).to eq Array
      expect(@logger.logged(:debug).last).to match(/:owner/)
      expect(@logger.logged(:debug).last).to match(/\[\["owner", "#{DATABASE_USER.upcase}"\], \["owner", "#{DATABASE_USER.upcase}"\]\]/)
    end

    it "should not have primary key trigger with bind usage" do
      expect(@conn.has_primary_key_trigger?("TEST_POSTS")).to eq false
      expect(@logger.logged(:debug).last).to match(/:owner/)
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\[\["owner", "#{DATABASE_USER.upcase}"\], \["trigger_name", "TEST_POSTS_PKT"\], \["owner", "#{DATABASE_USER.upcase}"\], \["table_name", "TEST_POSTS"\]\]/)
    end

    it "should return content from columns with bind usage" do
      expect(@conn.columns("TEST_POSTS").length).to be > 0
      expect(@logger.logged(:debug).last).to match(/:owner/)
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\[\["owner", "#{DATABASE_USER.upcase}"\], \["table_name", "TEST_POSTS"\]\]/)
    end

    it "should return pk and sequence from pk_and_sequence_for with bind usage" do
      expect(@conn.pk_and_sequence_for("TEST_POSTS").length).to eq 2
      expect(@logger.logged(:debug).last).to match(/:owner/)
      expect(@logger.logged(:debug).last).to match(/\[\["owner", "#{DATABASE_USER.upcase}"\], \["table_name", "TEST_POSTS"\]\]/)
    end

    it "should return pk from primary_keys with bind usage" do
      expect(@conn.primary_keys("TEST_POSTS")).to eq ["id"]
      expect(@logger.logged(:debug).last).to match(/:owner/)
      expect(@logger.logged(:debug).last).to match(/\[\["owner", "#{DATABASE_USER.upcase}"\], \["table_name", "TEST_POSTS"\]\]/)
    end

    it "should return false from temporary_table? with bind usage" do
      expect(@conn.temporary_table?("TEST_POSTS")).to eq false
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\[\["table_name", "TEST_POSTS"\]\]/)
    end

  end

  describe "Transaction" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
      end
      Thread.report_on_exception, @original_report_on_exception = false, Thread.report_on_exception if Thread.respond_to?(:report_on_exception)
    end

    it "Raises Deadlocked when a deadlock is encountered" do
      skip "Skip temporary due to #1599" if ActiveRecord::Base.connection.supports_fetch_first_n_rows_and_offset?
      expect {
        barrier = Concurrent::CyclicBarrier.new(2)

        t1 = TestPost.create(title: "one")
        t2 = TestPost.create(title: "two")

        thread = Thread.new do
          TestPost.transaction do
            t1.lock!
            barrier.wait
            t2.update_attributes(title: "one")
          end
        end

        begin
          TestPost.transaction do
            t2.lock!
            barrier.wait
            t1.update_attributes(title: "two")
          end
        ensure
          thread.join
        end
      }.to raise_error(ActiveRecord::Deadlocked)
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost") rescue nil
      ActiveRecord::Base.clear_cache!
      Thread.report_on_exception = @original_report_on_exception if Thread.respond_to?(:report_on_exception)
    end
  end
end
