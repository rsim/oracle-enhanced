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
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = nil
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
      @conn = ActiveRecord::Base.connection
      @conn.clear_columns_cache
    end

    after(:each) do
      clear_logger
    end

    describe "without column caching" do

      before(:each) do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = false
      end

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

    describe "with column caching" do

      before(:each) do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
      end

      it "should get columns from database at first time" do
        expect(TestEmployee.connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get columns from cache at second time" do
        TestEmployee.connection.columns("test_employees")
        @logger.clear(:debug)
        expect(TestEmployee.connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to be_blank
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should get primary key from cache at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to be_blank
      end

      it "should store primary key as nil in cache at first time for table without primary key" do
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees_without_pk")).to eq(nil)
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for("test_employees_without_pk")).to eq(nil)
        expect(@logger.logged(:debug).last).to be_blank
      end

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
      pk = TestPost.columns_hash[TestPost.primary_key]
      sub = Arel::Nodes::BindParam.new(nil).to_sql
      binds = [ActiveRecord::Relation::QueryAttribute.new(pk, 1, ActiveRecord::Type::Integer.new)]

      expect {
        4.times do |i|
          @conn.exec_query("SELECT * FROM test_posts WHERE #{i}=#{i} AND id = #{sub}", "SQL", binds)
        end
      }.to change(@statements, :length).by(+3)
    end

    it "should cache UPDATE statements with bind variables" do
      expect {
        pk = TestPost.columns_hash[TestPost.primary_key]
        sub = Arel::Nodes::BindParam.new(nil).to_sql
        binds = [ActiveRecord::Relation::QueryAttribute.new(pk, 1, ActiveRecord::Type::Integer.new)]
        @conn.exec_update("UPDATE test_posts SET id = #{sub}", "SQL", binds)
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
      skip "Skip until further investigation made for #908 JRuby and #1386 for CRuby"
      pk = TestPost.columns_hash[TestPost.primary_key]
      sub = Arel::Nodes::BindParam.new.to_sql
      binds = [ActiveRecord::Relation::QueryAttribute.new(pk, 1, ActiveRecord::Type::Integer.new)]
      explain = @conn.explain(TestPost.where(TestPost.arel_table[pk.name].eq(sub)), binds)
      expect(explain).to include("Cost")
      expect(explain).to include("INDEX UNIQUE SCAN")
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
end
