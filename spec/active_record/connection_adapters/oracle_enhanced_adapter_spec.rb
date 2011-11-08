require 'spec_helper'

describe "OracleEnhancedAdapter establish connection" do

  it "should connect to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should connect to database as SYSDBA" do
    ActiveRecord::Base.establish_connection(SYS_CONNECTION_PARAMS)
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should be active after connection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.should be_active
  end

  it "should not be active after disconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.disconnect!
    ActiveRecord::Base.connection.should_not be_active
  end

  it "should be active after reconnection to database" do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Base.connection.reconnect!
    ActiveRecord::Base.connection.should be_active
  end
  
end

describe "OracleEnhancedAdapter" do
  include LoggerSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end
  
  describe "database session store" do
    before(:all) do
      @conn.execute "DROP TABLE sessions" rescue nil
      @conn.execute "DROP SEQUENCE sessions_seq" rescue nil
      @conn = ActiveRecord::Base.connection
      @conn.execute <<-SQL
        CREATE TABLE sessions (
          id          NUMBER(38,0) NOT NULL,
          session_id  VARCHAR2(255) DEFAULT NULL,
          data        CLOB DEFAULT NULL,
          created_at  DATE DEFAULT NULL,
          updated_at  DATE DEFAULT NULL,
          PRIMARY KEY (ID)
        )
      SQL
      @conn.execute <<-SQL
        CREATE SEQUENCE sessions_seq  MINVALUE 1 MAXVALUE 999999999999999999999999999
          INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
      SQL
      if ENV['RAILS_GEM_VERSION'] >= '2.3'
        @session_class = ActiveRecord::SessionStore::Session
      else
        @session_class = CGI::Session::ActiveRecordStore::Session
      end
    end

    after(:all) do
      @conn.execute "DROP TABLE sessions"
      @conn.execute "DROP SEQUENCE sessions_seq"
    end

    it "should create sessions table" do
      ActiveRecord::Base.connection.tables.grep("sessions").should_not be_empty
    end

    it "should save session data" do
      @session = @session_class.new :session_id => "111111", :data  => "something" #, :updated_at => Time.now
      @session.save!
      @session = @session_class.find_by_session_id("111111")
      @session.data.should == "something"
    end

    it "should change session data when partial updates enabled" do
      return pending("Not in this ActiveRecord version") unless @session_class.respond_to?(:partial_updates=)
      @session_class.partial_updates = true
      @session = @session_class.new :session_id => "222222", :data  => "something" #, :updated_at => Time.now
      @session.save!
      @session = @session_class.find_by_session_id("222222")
      @session.data = "other thing"
      @session.save!
      # second save should call again blob writing callback
      @session.save!
      @session = @session_class.find_by_session_id("222222")
      @session.data.should == "other thing"
    end

    it "should have one enhanced_write_lobs callback" do
      return pending("Not in this ActiveRecord version") unless @session_class.respond_to?(:after_save_callback_chain)
      @session_class.after_save_callback_chain.select{|cb| cb.method == :enhanced_write_lobs}.should have(1).record
    end

    it "should not set sessions table session_id column type as integer if emulate_integers_by_column_name is true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
      columns = @conn.columns('sessions')
      column = columns.detect{|c| c.name == "session_id"}
      column.type.should == :string
    end

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
      TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
    end

    it "should ignore specified table columns specified in several lines" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number
        ignore_table_columns  :hire_date
      end
      TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
    end

    it "should not ignore unspecified table columns" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number, :hire_date
      end
      TestEmployee.connection.columns('test_employees').select{|c| c.name == 'email' }.should_not be_empty
    end

    it "should ignore specified table columns in other connection" do
      class ::TestEmployee < ActiveRecord::Base
        ignore_table_columns  :phone_number, :hire_date
      end
      # establish other connection
      other_conn = ActiveRecord::Base.oracle_enhanced_connection(CONNECTION_PARAMS)
      other_conn.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
    end

  end

  describe "cache table columns" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @conn.execute "DROP TABLE test_employees" rescue nil
      @oracle11g = !! @conn.select_value("SELECT * FROM v$version WHERE banner LIKE 'Oracle%11g%'")
      @conn.execute <<-SQL
        CREATE TABLE test_employees (
          id            NUMBER PRIMARY KEY,
          first_name    VARCHAR2(20),
          last_name     VARCHAR2(25),
          #{ @oracle11g ? "full_name AS (first_name || ' ' || last_name)," : "full_name VARCHAR2(46),"}
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
        set_table_name "test_employees"
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
        pending "Not supported in this database version" unless @oracle11g
        te = TestEmployee.connection.columns('test_employees').detect(&:virtual?)
        te.name.should == 'full_name'
      end

      it "should get columns from database at first time" do
        TestEmployee.connection.columns('test_employees').map(&:name).should == @column_names
        @logger.logged(:debug).last.should =~ /select .* from all_tab_cols/im
      end

      it "should get columns from database at second time" do
        TestEmployee.connection.columns('test_employees')
        @logger.clear(:debug)
        TestEmployee.connection.columns('test_employees').map(&:name).should == @column_names
        @logger.logged(:debug).last.should =~ /select .* from all_tab_cols/im
      end

      it "should get primary key from database at first time" do
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.logged(:debug).last.should =~ /select .* from all_constraints/im
      end

      it "should get primary key from database at first time" do
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.clear(:debug)
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.logged(:debug).last.should =~ /select .* from all_constraints/im
      end

      it "should have correct sql types when 2 models are using the same table and AR query cache is enabled" do
        @conn.cache do
          TestEmployee.columns.map(&:sql_type).should == @column_sql_types
          TestEmployee2.columns.map(&:sql_type).should == @column_sql_types
        end
      end

    end

    describe "with column caching" do

      before(:each) do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
      end

      it "should get columns from database at first time" do
        TestEmployee.connection.columns('test_employees').map(&:name).should == @column_names
        @logger.logged(:debug).last.should =~ /select .* from all_tab_cols/im
      end

      it "should get columns from cache at second time" do
        TestEmployee.connection.columns('test_employees')
        @logger.clear(:debug)
        TestEmployee.connection.columns('test_employees').map(&:name).should == @column_names
        @logger.logged(:debug).last.should be_blank
      end

      it "should get primary key from database at first time" do
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.logged(:debug).last.should =~ /select .* from all_constraints/im
      end

      it "should get primary key from cache at first time" do
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.clear(:debug)
        TestEmployee.connection.pk_and_sequence_for('test_employees').should == ['id', nil]
        @logger.logged(:debug).last.should be_blank
      end

      it "should store primary key as nil in cache at first time for table without primary key" do
        TestEmployee.connection.pk_and_sequence_for('test_employees_without_pk').should == nil
        @logger.clear(:debug)
        TestEmployee.connection.pk_and_sequence_for('test_employees_without_pk').should == nil
        @logger.logged(:debug).last.should be_blank
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
        set_primary_key :employee_id
      end
    end

    after(:all) do
      Object.send(:remove_const, "TestEmployee")
      @conn.execute "DROP TABLE test_employees"
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should tell ActiveRecord that count distinct is supported" do
      ActiveRecord::Base.connection.supports_count_distinct?.should be_true
    end

    it "should execute correct SQL COUNT DISTINCT statement" do
      lambda { TestEmployee.count(:employee_id, :distinct => true) }.should_not raise_error
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
        TestReservedWord.columns_hash[attr.to_s].name.should == attr.to_s
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
        record.send(k).should == v
      end
    end

    it "should remove double quotes in column quoting" do
      ActiveRecord::Base.connection.quote_column_name('aaa "bbb" ccc').should == '"aaa bbb ccc"'
    end

  end

  describe "valid table names" do
    before(:all) do
      @adapter = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
    end

    it "should be valid with letters and digits" do
      @adapter.valid_table_name?("abc_123").should be_true
    end

    it "should be valid with schema name" do
      @adapter.valid_table_name?("abc_123.def_456").should be_true
    end

    it "should be valid with $ in name" do
      @adapter.valid_table_name?("sys.v$session").should be_true
    end

    it "should be valid with upcase schema name" do
      @adapter.valid_table_name?("ABC_123.DEF_456").should be_true
    end

    it "should be valid with irregular schema name and database links" do
      @adapter.valid_table_name?('abc$#_123.abc$#_123@abc$#@._123').should be_true
    end

    it "should not be valid with two dots in name" do
      @adapter.valid_table_name?("abc_123.def_456.ghi_789").should be_false
    end

    it "should not be valid with invalid characters" do
      @adapter.valid_table_name?("warehouse-things").should be_false
    end

    it "should not be valid with for camel-case" do
      @adapter.valid_table_name?("Abc").should be_false
      @adapter.valid_table_name?("aBc").should be_false
      @adapter.valid_table_name?("abC").should be_false
    end
    
    it "should not be valid for names > 30 characters" do
      @adapter.valid_table_name?("a" * 31).should be_false
    end
    
    it "should not be valid for schema names > 30 characters" do
      @adapter.valid_table_name?(("a" * 31) + ".validname").should be_false
    end
    
    it "should not be valid for database links > 128 characters" do
      @adapter.valid_table_name?("name@" + "a" * 129).should be_false
    end
    
    it "should not be valid for names that do not begin with alphabetic characters" do
      @adapter.valid_table_name?("1abc").should be_false
      @adapter.valid_table_name?("_abc").should be_false
      @adapter.valid_table_name?("abc.1xyz").should be_false
      @adapter.valid_table_name?("abc._xyz").should be_false
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
        set_table_name "warehouse-things"
      end

      wh = WarehouseThing.create!(:name => "Foo", :foo => 2)
      wh.id.should_not be_nil

      @conn.tables.should include("warehouse-things")
    end

    it "should allow creation of a table with CamelCase name" do
      create_camel_case_table
      class ::CamelCase < ActiveRecord::Base
        set_table_name "CamelCase"
      end

      cc = CamelCase.create!(:name => "Foo", :foo => 2)
      cc.id.should_not be_nil
    
      @conn.tables.should include("CamelCase")
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
        t.timestamps
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
      TestPost.set_table_name "test_posts"
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
      TestPost.column_names.should == ["id", "title", "body", "created_at", "updated_at"]
    end

    it "should create record" do
      p = TestPost.create(:title => "Title", :body => "Body")
      p.id.should_not be_nil
      TestPost.find(p.id).should_not be_nil
    end

  end

  describe "session information" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    it "should get current database name" do
      # get database name if using //host:port/database connection string
      database_name = CONNECTION_PARAMS[:database].split('/').last
      @conn.current_database.upcase.should == database_name.upcase
    end

    it "should get current database session user" do
      @conn.current_user.upcase.should == CONNECTION_PARAMS[:username].upcase
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
      @conn.temporary_table?("foos").should be_true
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
      posts = TestPost.includes(:test_comments).all
      posts.size.should == @ids.size
    end

  end if ENV['RAILS_GEM_VERSION'] >= '3.1'

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
      pk = TestPost.columns.find { |c| c.primary }
      sub = @conn.substitute_at(pk, 0)
      binds = [[pk, 1]]

      lambda {
        4.times do |i|
          @conn.exec_query("SELECT * FROM test_posts WHERE #{i}=#{i} AND id = #{sub}", "SQL", binds)
        end
      }.should change(@statements, :length).by(+3)
    end

    it "should cache UPDATE statements with bind variables" do
      lambda {
        pk = TestPost.columns.find { |c| c.primary }
        sub = @conn.substitute_at(pk, 0)
        binds = [[pk, 1]]
        @conn.exec_update("UPDATE test_posts SET id = #{sub}", "SQL", binds)
      }.should change(@statements, :length).by(+1)
    end

    it "should not cache UPDATE statements without bind variables" do
      lambda {
        binds = []
        @conn.exec_update("UPDATE test_posts SET id = 1", "SQL", binds)
      }.should_not change(@statements, :length)
    end
  end if ENV['RAILS_GEM_VERSION'] >= '3.1'

  describe "explain" do
    before(:all) do
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
      explain.should include("Cost")
      explain.should include("INDEX UNIQUE SCAN")
    end
  end if ENV['RAILS_GEM_VERSION'] >= '3.2'
end
