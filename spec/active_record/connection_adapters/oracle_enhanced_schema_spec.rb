require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter schema definition" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "table and sequence creation with non-default primary key" do

    before(:all) do
      schema_define do
        create_table :keyboards, :force => true, :id  => false do |t|
          t.primary_key :key_number
          t.string      :name
        end
        create_table :id_keyboards, :force => true do |t|
          t.string      :name
        end
      end
      class ::Keyboard < ActiveRecord::Base
        set_primary_key :key_number
      end
      class ::IdKeyboard < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :keyboards
        drop_table :id_keyboards
      end
      Object.send(:remove_const, "Keyboard")
      Object.send(:remove_const, "IdKeyboard")
    end

    it "should create sequence for non-default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(Keyboard.sequence_name).should_not be_nil
    end

    it "should create sequence for default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(IdKeyboard.sequence_name).should_not be_nil
    end
  end

  describe "sequence creation parameters" do

    def create_test_employees_table(sequence_start_value = nil)
      schema_define do
        create_table :test_employees, sequence_start_value ? {:sequence_start_value => sequence_start_value} : {} do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end

    def save_default_sequence_start_value
      @saved_sequence_start_value = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value
    end

    def restore_default_sequence_start_value
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = @saved_sequence_start_value
    end

    before(:each) do
      save_default_sequence_start_value
    end
    after(:each) do
      restore_default_sequence_start_value
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
    end

    it "should use default sequence start value 10000" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value.should == 10000

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 10000
    end

    it "should use specified default sequence start value" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 1

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 1
    end

    it "should use sequence start value from table definition" do
      create_test_employees_table(10)
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 10
    end

    it "should use sequence start value and other options from table definition" do
      create_test_employees_table("100 NOCACHE INCREMENT BY 10")
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 100
      employee = TestEmployee.create!
      employee.id.should == 110
    end

  end

  describe "create table with primary key trigger" do
    def create_table_with_trigger(options = {})
      options.merge! :primary_key_trigger => true, :force => true
      schema_define do
        create_table :test_employees, options do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end

    def create_table_and_separately_trigger(options = {})
      options.merge! :force => true
      schema_define do
        create_table :test_employees, options do |t|
          t.string      :first_name
          t.string      :last_name
        end
        add_primary_key_trigger :test_employees, options
      end
    end

    after(:all) do
      seq_name = @sequence_name
      schema_define do
        drop_table :test_employees, (seq_name ? {:sequence_name => seq_name} : {})
      end
      Object.send(:remove_const, "TestEmployee")
      @conn.clear_prefetch_primary_key
    end

    describe "with default primary key" do
      before(:all) do
        create_table_with_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == insert_id
      end
      
      it "should create new record for model" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == e.id
      end
    end

    describe "with separate creation of primary key trigger" do
      before(:all) do
        create_table_and_separately_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == insert_id
      end
      
      it "should create new record for model" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == e.id
      end
    end

    describe "with non-default primary key and non-default sequence name" do
      before(:all) do
        @primary_key = "employee_id"
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:primary_key => @primary_key, :sequence_name => @sequence_name)
        class ::TestEmployee < ActiveRecord::Base
          set_primary_key "employee_id"
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, @primary_key)
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == insert_id
      end

      it "should create new record for model with autogenerated sequence option" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == e.id
      end
    end

    describe "with non-default sequence name and non-default trigger name" do
      before(:all) do
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:sequence_name => @sequence_name, :trigger_name => "test_employees_t1")
        class ::TestEmployee < ActiveRecord::Base
          set_sequence_name :autogenerated
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == insert_id
      end

      it "should create new record for model with autogenerated sequence option" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == e.id
      end
    end

  end

  describe "table and column comments" do

    def create_test_employees_table(table_comment=nil, column_comments={})
      schema_define do
        create_table :test_employees, :comment => table_comment do |t|
          t.string      :first_name, :comment => column_comments[:first_name]
          t.string      :last_name, :comment => column_comments[:last_name]
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.table_name_prefix = nil
    end

    it "should create table with table comment" do
      table_comment = "Test Employees"
      create_test_employees_table(table_comment)
      class ::TestEmployee < ActiveRecord::Base; end

      @conn.table_comment("test_employees").should == table_comment
      TestEmployee.table_comment.should == table_comment
    end

    it "should create table with columns comment" do
      column_comments = {:first_name => "Given Name", :last_name => "Surname"}
      create_test_employees_table(nil, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      [:first_name, :last_name].each do |attr|
        @conn.column_comment("test_employees", attr.to_s).should == column_comments[attr]
      end
      [:first_name, :last_name].each do |attr|
        TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
      end
    end

    it "should create table with table and columns comment and custom table name prefix" do
      ActiveRecord::Base.table_name_prefix = "xxx_"
      table_comment = "Test Employees"
      column_comments = {:first_name => "Given Name", :last_name => "Surname"}
      create_test_employees_table(table_comment, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      @conn.table_comment(TestEmployee.table_name).should == table_comment
      TestEmployee.table_comment.should == table_comment
      [:first_name, :last_name].each do |attr|
        @conn.column_comment(TestEmployee.table_name, attr.to_s).should == column_comments[attr]
      end
      [:first_name, :last_name].each do |attr|
        TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
      end
    end

  end

  describe "create triggers" do

    before(:all) do
      schema_define do
        create_table  :test_employees do |t|
          t.string    :first_name
          t.string    :last_name
        end
      end
      class ::TestEmployee < ActiveRecord::Base; end
    end

    after(:all) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
    end

    it "should create table trigger with :new reference" do
      lambda do
        @conn.execute <<-SQL
        CREATE OR REPLACE TRIGGER test_employees_pkt
        BEFORE INSERT ON test_employees FOR EACH ROW
        BEGIN
          IF inserting THEN
            IF :new.id IS NULL THEN
              SELECT test_employees_seq.NEXTVAL INTO :new.id FROM dual;
            END IF;
          END IF;
        END;
        SQL
      end.should_not raise_error
    end
  end

  describe "add index" do

    it "should return default index name if it is not larger than 30 characters" do
      @conn.index_name("employees", :column => "first_name").should == "index_employees_on_first_name"
    end

    it "should return shortened index name by removing 'index', 'on' and 'and' keywords" do
      @conn.index_name("employees", :column => ["first_name", "email"]).should == "i_employees_first_name_email"
    end

    it "should return shortened index name by shortening table and column names" do
      @conn.index_name("employees", :column => ["first_name", "last_name"]).should == "i_emp_fir_nam_las_nam"
    end

    it "should raise error if too large index name cannot be shortened" do
      @conn.index_name("test_employees", :column => ["first_name", "middle_name", "last_name"]).should ==
        'i'+Digest::SHA1.hexdigest("index_test_employees_on_first_name_and_middle_name_and_last_name")[0,29]
    end

  end

  describe "ignore options for LOB columns" do
    after(:each) do
      schema_define do
        drop_table :test_posts
      end
    end

    it "should ignore :limit option for :text column" do
      lambda do
        schema_define do
          create_table :test_posts, :force => true do |t|
            t.text :body, :limit => 10000
          end
        end
      end.should_not raise_error
    end

    it "should ignore :limit option for :binary column" do
      lambda do
        schema_define do
          create_table :test_posts, :force => true do |t|
            t.binary :picture, :limit => 10000
          end
        end
      end.should_not raise_error
    end

  end

  describe "foreign key constraints" do
    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
          t.integer :post_id
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should add foreign key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TEST_COMMENTS_TEST_POST_ID_FK/}
    end

    it "should add foreign key with name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "comments_posts_fk"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.COMMENTS_POSTS_FK/}
    end

    it "should add foreign key with long name which is shortened" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "test_comments_test_post_id_foreign_key"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TES_COM_TES_POS_ID_FOR_KEY/}
    end

    it "should add foreign key with very long name which is shortened" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "long_prefix_test_comments_test_post_id_foreign_key"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~
        /ORA-02291.*\.C#{Digest::SHA1.hexdigest("long_prefix_test_comments_test_post_id_foreign_key")[0,29].upcase}/}
    end

    it "should add foreign key with column" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :column => "post_id"
      end
      lambda do
        TestComment.create(:body => "test", :post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TEST_COMMENTS_POST_ID_FK/}
    end

    it "should add foreign key with delete dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :delete
      end
      p = TestPost.create(:title => "test")
      c = TestComment.create(:body => "test", :test_post => p)
      TestPost.delete(p.id)
      TestComment.find_by_id(c.id).should be_nil
    end

    it "should add foreign key with nullify dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :nullify
      end
      p = TestPost.create(:title => "test")
      c = TestComment.create(:body => "test", :test_post => p)
      TestPost.delete(p.id)
      TestComment.find_by_id(c.id).test_post_id.should be_nil
    end

    it "should remove foreign key by table name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, :test_posts
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

    it "should remove foreign key by constraint name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "comments_posts_fk"
        remove_foreign_key :test_comments, :name => "comments_posts_fk"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

    it "should remove foreign key by column name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, :column => "test_post_id"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

  end

  describe "foreign key in table definition" do
    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should add foreign key in create_table" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
          t.foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in create_table references" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post, :foreign_key => true
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in change_table" do
      return pending("Not in this ActiveRecord version") unless ENV['RAILS_GEM_VERSION'] >= '2.1'
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
        end
        change_table :test_comments do |t|
          t.foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in change_table references" do
      return pending("Not in this ActiveRecord version") unless ENV['RAILS_GEM_VERSION'] >= '2.1'
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
        end
        change_table :test_comments do |t|
          t.references :test_post, :foreign_key => true
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should remove foreign key by table name" do
      return pending("Not in this ActiveRecord version") unless ENV['RAILS_GEM_VERSION'] >= '2.1'
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
        end
        change_table :test_comments do |t|
          t.foreign_key :test_posts
        end
        change_table :test_comments do |t|
          t.remove_foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

  end

  describe "disable referential integrity" do
    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post, :foreign_key => true
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should disable all foreign keys" do
      lambda do
        @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (1, 'test', 1)"
      end.should raise_error
      @conn.disable_referential_integrity do
        lambda do
          @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (2, 'test', 2)"
          @conn.execute "INSERT INTO test_posts (id, title) VALUES (2, 'test')"
        end.should_not raise_error
      end
      lambda do
        @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (3, 'test', 3)"
      end.should raise_error
    end

  end

  describe "synonyms" do
    before(:all) do
      @db_link = "db_link"
      @username = @db_link_username = CONNECTION_PARAMS[:username]
      @db_link_password = CONNECTION_PARAMS[:password]
      @db_link_database = CONNECTION_PARAMS[:database]
      @conn.execute "DROP DATABASE LINK #{@db_link}" rescue nil
      @conn.execute "CREATE DATABASE LINK #{@db_link} CONNECT TO #{@db_link_username} IDENTIFIED BY \"#{@db_link_password}\" USING '#{@db_link_database}'"
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      @conn.execute "DROP DATABASE LINK #{@db_link}" rescue nil
    end

    before(:each) do
      class ::TestPost < ActiveRecord::Base
        set_table_name "synonym_to_posts"
      end
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define do
        remove_synonym :synonym_to_posts
        remove_synonym :synonym_to_posts_seq
      end
    end

    it "should create synonym to table and sequence" do
      schema_name = @username
      schema_define do
        add_synonym :synonym_to_posts, "#{schema_name}.test_posts", :force => true
        add_synonym :synonym_to_posts_seq, "#{schema_name}.test_posts_seq", :force => true
      end
      lambda do
        TestPost.create(:title => "test")
      end.should_not raise_error
    end

    it "should create synonym to table over database link" do
      db_link = @db_link
      schema_define do
        add_synonym :synonym_to_posts, "test_posts@#{db_link}", :force => true
        add_synonym :synonym_to_posts_seq, "test_posts_seq@#{db_link}", :force => true
      end
      lambda do
        TestPost.create(:title => "test")
      end.should_not raise_error
    end

  end

  describe "alter columns with column cache" do
    include LoggerSpecHelper

    before(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
    end

    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = nil
    end

    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title, :null => false
        end
      end
      class ::TestPost < ActiveRecord::Base; end
      TestPost.columns_hash['title'].null.should be_false
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define { drop_table :test_posts }
    end

    it "should change column to nullable" do
      schema_define do
        change_column :test_posts, :title, :string, :null => true
      end
      TestPost.reset_column_information
      TestPost.columns_hash['title'].null.should be_true
    end

    it "should add column" do
      schema_define do
        add_column :test_posts, :body, :string
      end
      TestPost.reset_column_information
      TestPost.columns_hash['body'].should_not be_nil
    end

    it "should rename column" do
      schema_define do
        rename_column :test_posts, :title, :subject
      end
      TestPost.reset_column_information
      TestPost.columns_hash['subject'].should_not be_nil
      TestPost.columns_hash['title'].should be_nil
    end

    it "should remove column" do
      schema_define do
        remove_column :test_posts, :title
      end
      TestPost.reset_column_information
      TestPost.columns_hash['title'].should be_nil
    end

  end

  describe "miscellaneous options" do
    before(:each) do
      @conn.instance_variable_set :@would_execute_sql, @would_execute_sql=''
      class <<@conn
        def execute(sql,name=nil); @would_execute_sql << sql << ";\n"; end
        def index_exists?(table_name, index_name, default); default; end
      end
    end

    after(:each) do
      class <<@conn
        remove_method :execute
      end
      @conn.instance_eval{ remove_instance_variable :@would_execute_sql }
    end
    
    it "should support the :options option to create_table" do
      schema_define do
        create_table :test_posts, :options=>'NOLOGGING', :force => true do |t|
          t.string :title, :null => false
        end
      end
      @would_execute_sql.should =~ /CREATE +TABLE .* \(.*\) NOLOGGING/
    end
    
    it "should support the :tablespace option to create_table" do
      schema_define do
        create_table :test_posts, :tablespace=>'bogus', :force => true do |t|
          t.string :title, :null => false
        end
      end
      @would_execute_sql.should =~ /CREATE +TABLE .* \(.*\) TABLESPACE bogus/
    end
    
    it "should support the :options option to add_index" do
      schema_define do
        add_index :keyboards, :name, :options=>'NOLOGGING'
      end
      @would_execute_sql.should =~ /CREATE +INDEX .* ON .* \(.*\) NOLOGGING/
    end
    
    it "should support the :tablespace option to add_index" do
      schema_define do
        add_index :keyboards, :name, :tablespace=>'bogus'
      end
      @would_execute_sql.should =~ /CREATE +INDEX .* ON .* \(.*\) TABLESPACE bogus/
    end
  end
end
