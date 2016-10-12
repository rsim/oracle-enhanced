require 'spec_helper'

describe "OracleEnhancedAdapter establish connection" do

  it "should connect to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).not_to be_nil
    expect(ActiveRecord::Base.connection.class).to eq(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter)
  end

  it "should connect to database as SYSDBA" do
    ActiveRecord::Base.establish_connection(SYS_CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).not_to be_nil
    expect(ActiveRecord::Base.connection.class).to eq(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter)
  end

  it "should be active after connection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    expect(ActiveRecord::Base.connection).to be_active
  end

  it "should not be active after disconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.disconnect!
    expect(ActiveRecord::Base.connection).not_to be_active
  end

  it "should be active after reconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.reconnect!
    expect(ActiveRecord::Base.connection).to be_active
  end

end

describe "OracleEnhancedAdapter" do
  include LoggerSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  describe "ignore specified table columns" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @conn.execute "DROP TABLE test_employees" rescue nil
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          id            NUMBER PRIMARY KEY,
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          email         VARCHAR2(25),
          phone_number  VARCHAR2(20),
          hire_date     DATE,
          job_id        NUMBER,
          salary        NUMBER,
          commission_pct  NUMBER(2,2),
          manager_id    NUMBER(6),
          department_id NUMBER(4,0),
          created_at    DATE
        )
      SQL
      @conn.execute "DROP SEQUENCE test_employees_seq" rescue nil
      @conn.execute <<-SQL
        CREATE SEQUENCE test_employees_seq  MINVALUE 1
          INCREMENT BY 1 START WITH 1 CACHE 20 NOORDER NOCYCLE
      SQL
    end

    after(:all) do
      @conn.execute "DROP TABLE test_employees"
      @conn.execute "DROP SEQUENCE test_employees_seq"
    end

    after(:each) do
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.connection.clear_ignored_table_columns
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should ignore specified table columns" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number, :hire_date
      end
      expect(TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }).to be_empty
    end

    it "should ignore specified table columns specified in several lines" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number
        ignore_table_columns  :hire_date
      end
      expect(TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }).to be_empty
    end

    it "should not ignore unspecified table columns" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number, :hire_date
      end
      expect(TestEmployee.connection.columns('test_employees').select{|c| c.name == 'email' }).not_to be_empty
    end

    it "should ignore specified table columns in other connection" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number, :hire_date
      end
      # establish other connection
      other_conn = ActiveRecord::Base.oracle_enhanced_connection(CONNECTION_PARAMS)
      expect(other_conn.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }).to be_empty
    end

  end

  describe "cache table columns" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @conn.execute "DROP TABLE test_employees" rescue nil
      @oracle11g_or_higher = !! @conn.select_value(
        "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 11")
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          id            NUMBER PRIMARY KEY,
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          #{ @oracle11g_or_higher ? "full_name AS (first_name || ' ' || last_name)," : "full_name VARCHAR2(46),"}
          hire_date     DATE
        )
      SQL
      @conn.execute <<-SQL
        CREATE TABLE test_employees_without_pk (
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          hire_date     DATE
        )
      SQL
      @column_names = ['id', 'first_name', 'last_name', 'full_name', 'hire_date']
      @column_sql_types = ["NUMBER", "VARCHAR2(20)", "VARCHAR2(25)", "VARCHAR2(46)", "DATE"]
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
      @conn.execute "DROP TABLE test_employees"
      @conn.execute "DROP TABLE test_employees_without_pk"
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = nil
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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

      it 'should identify virtual columns as such' do
        skip "Not supported in this database version" unless @oracle11g_or_higher
        te = TestEmployee.connection.columns('test_employees').detect(&:virtual?)
        expect(te.name).to eq('full_name')
      end

      it "should get columns from database at first time" do
        expect(TestEmployee.connection.columns('test_employees').map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get columns from database at second time" do
        TestEmployee.connection.columns('test_employees')
        @logger.clear(:debug)
        expect(TestEmployee.connection.columns('test_employees').map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
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
        expect(TestEmployee.connection.columns('test_employees').map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to match(/select .* from all_tab_cols/im)
      end

      it "should get columns from cache at second time" do
        TestEmployee.connection.columns('test_employees')
        @logger.clear(:debug)
        expect(TestEmployee.connection.columns('test_employees').map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).last).to be_blank
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should get primary key from cache at first time" do
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees')).to eq(['id', nil])
        expect(@logger.logged(:debug).last).to be_blank
      end

      it "should store primary key as nil in cache at first time for table without primary key" do
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees_without_pk')).to eq(nil)
        @logger.clear(:debug)
        expect(TestEmployee.connection.pk_and_sequence_for('test_employees_without_pk')).to eq(nil)
        expect(@logger.logged(:debug).last).to be_blank
      end

    end

  end

  describe "without composite_primary_keys" do

    before(:all) do
      @conn = ActiveRecord::Base.connection
      @conn.execute "DROP TABLE test_employees" rescue nil
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          employee_id   NUMBER PRIMARY KEY,
          name          VARCHAR2(50)
        )
      SQL
      Object.send(:remove_const, 'CompositePrimaryKeys') if defined?(CompositePrimaryKeys)
      class ::TestEmployee < ActiveRecord::Base
        self.primary_key = :employee_id
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      @conn.execute "DROP TABLE test_employees"
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should tell ActiveRecord that count distinct is supported" do
      expect(ActiveRecord::Base.connection.supports_count_distinct?).to be_truthy
    end

    it "should execute correct SQL COUNT DISTINCT statement" do
      expect { TestEmployee.distinct.count(:employee_id) }.not_to raise_error
    end

  end


  describe "reserved words column quoting" do

    before(:all) do
      schema_define do
        create_table :test_reserved_words do |t|
          t.string      :varchar2
          t.integer     :integer
          t.text        :comment
        end
      end
      class ::TestReservedWord < ActiveRecord::Base; end
    end

    after(:all) do
      schema_define do
        drop_table :test_reserved_words
      end
      Object.send(:remove_const, "TestReservedWord")
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "should create table" do
      [:varchar2, :integer, :comment].each do |attr|
        expect(TestReservedWord.columns_hash[attr.to_s].name).to eq(attr.to_s)
      end
    end

    it "should create record" do
      attrs = {
        :varchar2 => 'dummy',
        :integer => 1,
        :comment => 'dummy'
      }
      record = TestReservedWord.create!(attrs)
      record.reload
      attrs.each do |k, v|
        expect(record.send(k)).to eq(v)
      end
    end

    it "should remove double quotes in column quoting" do
      expect(ActiveRecord::Base.connection.quote_column_name('aaa "bbb" ccc')).to eq('"aaa bbb ccc"')
    end

  end

  describe "valid table names" do
    before(:all) do
      @adapter = ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting
    end

    it "should be valid with letters and digits" do
      expect(@adapter.valid_table_name?("abc_123")).to be_truthy
    end

    it "should be valid with schema name" do
      expect(@adapter.valid_table_name?("abc_123.def_456")).to be_truthy
    end

    it "should be valid with $ in name" do
      expect(@adapter.valid_table_name?("sys.v$session")).to be_truthy
    end

    it "should be valid with upcase schema name" do
      expect(@adapter.valid_table_name?("ABC_123.DEF_456")).to be_truthy
    end

    it "should be valid with irregular schema name and database links" do
      expect(@adapter.valid_table_name?('abc$#_123.abc$#_123@abc$#@._123')).to be_truthy
    end

    it "should not be valid with two dots in name" do
      expect(@adapter.valid_table_name?("abc_123.def_456.ghi_789")).to be_falsey
    end

    it "should not be valid with invalid characters" do
      expect(@adapter.valid_table_name?("warehouse-things")).to be_falsey
    end

    it "should not be valid with for camel-case" do
      expect(@adapter.valid_table_name?("Abc")).to be_falsey
      expect(@adapter.valid_table_name?("aBc")).to be_falsey
      expect(@adapter.valid_table_name?("abC")).to be_falsey
    end

    it "should not be valid for names > 30 characters" do
      expect(@adapter.valid_table_name?("a" * 31)).to be_falsey
    end

    it "should not be valid for schema names > 30 characters" do
      expect(@adapter.valid_table_name?(("a" * 31) + ".validname")).to be_falsey
    end

    it "should not be valid for database links > 128 characters" do
      expect(@adapter.valid_table_name?("name@" + "a" * 129)).to be_falsey
    end

    it "should not be valid for names that do not begin with alphabetic characters" do
      expect(@adapter.valid_table_name?("1abc")).to be_falsey
      expect(@adapter.valid_table_name?("_abc")).to be_falsey
      expect(@adapter.valid_table_name?("abc.1xyz")).to be_falsey
      expect(@adapter.valid_table_name?("abc._xyz")).to be_falsey
    end
  end

  describe "table quoting" do

    def create_warehouse_things_table
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table "warehouse-things" do |t|
            t.string      :name
            t.integer     :foo
          end
        end
      end
    end

    def create_camel_case_table
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table "CamelCase" do |t|
            t.string      :name
            t.integer     :foo
          end
        end
      end
    end

    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    after(:each) do
      ActiveRecord::Schema.define do
        suppress_messages do
          drop_table "warehouse-things" rescue nil
          drop_table "CamelCase" rescue nil
        end
      end
      Object.send(:remove_const, "WarehouseThing") rescue nil
      Object.send(:remove_const, "CamelCase") rescue nil
    end

    it "should allow creation of a table with non alphanumeric characters" do
      create_warehouse_things_table
      class ::WarehouseThing < ActiveRecord::Base
        self.table_name = "warehouse-things"
      end

      wh = WarehouseThing.create!(:name => "Foo", :foo => 2)
      expect(wh.id).not_to be_nil

      expect(@conn.tables).to include("warehouse-things")
    end

    it "should allow creation of a table with CamelCase name" do
      create_camel_case_table
      class ::CamelCase < ActiveRecord::Base
        self.table_name = "CamelCase"
      end

      cc = CamelCase.create!(:name => "Foo", :foo => 2)
      expect(cc.id).not_to be_nil

      expect(@conn.tables).to include("CamelCase")
    end

    it "properly quotes database links" do
      expect(@conn.quote_table_name('asdf@some.link')).to eq('"ASDF"@"SOME.LINK"')
    end
  end

  describe "access table over database link" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @db_link = "db_link"
      @sys_conn = ActiveRecord::Base.oracle_enhanced_connection(SYSTEM_CONNECTION_PARAMS)
      @sys_conn.drop_table :test_posts rescue nil
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
      @sys_conn.drop_table :test_posts rescue nil
      Object.send(:remove_const, "TestPost") rescue nil
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should verify database link" do
      @conn.select_value("select * from dual@#{@db_link}") == 'X'
    end

    it "should get column names" do
      expect(TestPost.column_names).to eq(["id", "title", "body", "created_at", "updated_at"])
    end

    it "should create record" do
      p = TestPost.create(:title => "Title", :body => "Body")
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
      database_name = CONNECTION_PARAMS[:database].split('/').last
      expect(@conn.current_database.upcase).to eq(database_name.upcase)
    end

    it "should get current database session user" do
      expect(@conn.current_user.upcase).to eq(CONNECTION_PARAMS[:username].upcase)
    end
  end

  describe "temporary tables" do
    before(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:table] = 'UNUSED'
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = 'UNUSED'
      @conn = ActiveRecord::Base.connection
    end
    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces={}
    end

    after(:each) do
      @conn.drop_table :foos rescue nil
    end
    it "should create ok" do
      @conn.create_table :foos, :temporary => true, :id => false do |t|
        t.integer :id
        t.text :bar
      end
    end
    it "should show up as temporary" do
      @conn.create_table :foos, :temporary => true, :id => false do |t|
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
          TestPost.create!(:id => id, :title => "Title #{id}")
          TestComment.create!(:test_post_id => id, :description => "Description #{id}")
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should load included association with more than 1000 records" do
      posts = TestPost.includes(:test_comments).to_a
      expect(posts.size).to eq(@ids.size)
    end

  end

  describe "with statement pool" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(:statement_limit => 3))
      @conn = ActiveRecord::Base.connection
      schema_define do
        drop_table :test_posts rescue nil
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should clear older cursors when statement limit is reached" do
      pk = TestPost.columns_hash[TestPost.primary_key]
      sub = Arel::Nodes::BindParam.new.to_sql
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
        sub = Arel::Nodes::BindParam.new.to_sql
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
        drop_table :test_posts rescue nil
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should explain query" do
      explain = TestPost.where(:id => 1).explain
      expect(explain).to include("Cost")
      expect(explain).to include("INDEX UNIQUE SCAN")
    end

    it "should explain query with binds" do
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
      @conn.execute "DROP TABLE test_employees" rescue nil
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          id            NUMBER PRIMARY KEY,
          sort_order    NUMBER(38,0),
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          updated_at    DATE,
          created_at    DATE
        )
      SQL
      @conn.execute "DROP SEQUENCE test_employees_seq" rescue nil
      @conn.execute <<-SQL
        CREATE SEQUENCE test_employees_seq  MINVALUE 1
          INCREMENT BY 1 START WITH 1 CACHE 20 NOORDER NOCYCLE
      SQL
      @employee = Class.new(ActiveRecord::Base) do
        self.table_name = :test_employees
      end
      i = 0
      @employee.create!(sort_order: i+=1, first_name: 'Peter',   last_name: 'Parker')
      @employee.create!(sort_order: i+=1, first_name: 'Tony',    last_name: 'Stark')
      @employee.create!(sort_order: i+=1, first_name: 'Steven',  last_name: 'Rogers')
      @employee.create!(sort_order: i+=1, first_name: 'Bruce',   last_name: 'Banner')
      @employee.create!(sort_order: i+=1, first_name: 'Natasha', last_name: 'Romanova')
    end

    after(:all) do
      @conn.execute "DROP TABLE test_employees"
      @conn.execute "DROP SEQUENCE test_employees_seq"
    end

    after(:each) do
      ActiveRecord::Base.connection.clear_ignored_table_columns
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          first_name    VARCHAR2(20)
       )
      SQL
    end

    after(:all) do
      @conn.execute "DROP TABLE test_employees"
    end

    it "returns true when passed a valid type" do
      column = @conn.columns('test_employees').find { |col| col.name == 'first_name' }
      expect(@conn.valid_type?(column.type)).to be true
    end

    it "returns false when passed an invalid type" do
      expect(@conn.valid_type?(:foobar)).to be false
    end
  end

  describe 'serialized column' do
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
      Object.send(:remove_const, 'TestSerializedColumn')
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it 'should serialize' do
      new_value = 'new_value'
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
end
