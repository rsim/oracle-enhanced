require 'spec_helper'

describe "OracleEnhancedAdapter schema definition" do
  include SchemaSpecHelper
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @oracle11g_or_higher = !! !! ActiveRecord::Base.connection.select_value(
      "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 11")
  end

  describe 'option to create sequence when adding a column' do
    before do
      @conn = ActiveRecord::Base.connection
      schema_define do
        create_table :keyboards, :force => true, :id  => false do |t|
          t.string      :name
        end
        add_column :keyboards, :id, :primary_key
      end
      class ::Keyboard < ActiveRecord::Base; end
    end

    it 'creates a sequence when adding a column with create_sequence = true' do
      _, sequence_name = ActiveRecord::Base.connection.pk_and_sequence_for_without_cache(:keyboards)

      sequence_name.should == Keyboard.sequence_name
    end
  end

  describe "table and sequence creation with non-default primary key" do

    before(:all) do
      @conn = ActiveRecord::Base.connection
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
        self.primary_key = :key_number
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should create sequence for non-default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(Keyboard.sequence_name).should_not be_nil
    end

    it "should create sequence for default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(IdKeyboard.sequence_name).should_not be_nil
    end
  end

  describe "default sequence name" do

    it "should return sequence name without truncating too much" do
      seq_name_length = ActiveRecord::Base.connection.sequence_name_length
      tname = "#{DATABASE_USER}" + "." +"a"*(seq_name_length - DATABASE_USER.length) + "z"*(DATABASE_USER).length
      ActiveRecord::Base.connection.default_sequence_name(tname).should match (/z_seq$/)
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

    before(:all) do
      @conn = ActiveRecord::Base.connection
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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

    def drop_table_with_trigger(options = {})
      seq_name = options[:sequence_name]
      schema_define do
        drop_table :test_employees, (seq_name ? {:sequence_name => seq_name} : {})
      end
      Object.send(:remove_const, "TestEmployee")
      @conn.clear_prefetch_primary_key
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    describe "with default primary key" do
      before(:all) do
        @conn = ActiveRecord::Base.connection
        create_table_with_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      after(:all) do
        drop_table_with_trigger
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

      it "should not generate NoMethodError for :returning_id:Symbol" do
        set_logger
        @conn.reconnect! unless @conn.active?
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Yasuo')", nil, "id")
        @logger.output(:error).should_not match(/^Could not log "sql.active_record" event. NoMethodError: undefined method `name' for :returning_id:Symbol/)
        clear_logger
      end

    end

    describe "with separate creation of primary key trigger" do
      before(:all) do
        ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
        @conn = ActiveRecord::Base.connection
        create_table_and_separately_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      after(:all) do
        drop_table_with_trigger
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
        ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
        @conn = ActiveRecord::Base.connection
        @primary_key = "employee_id"
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:primary_key => @primary_key, :sequence_name => @sequence_name)
        class ::TestEmployee < ActiveRecord::Base
          self.primary_key = "employee_id"
        end
      end

      after(:all) do
        drop_table_with_trigger(:sequence_name => @sequence_name)
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
        ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
        @conn = ActiveRecord::Base.connection
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:sequence_name => @sequence_name, :trigger_name => "test_employees_t1")
        class ::TestEmployee < ActiveRecord::Base
          self.sequence_name = :autogenerated
        end
      end

      after(:all) do
        drop_table_with_trigger(:sequence_name => @sequence_name)
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

    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    after(:each) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.table_name_prefix = ''
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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

  describe "drop tables" do
    before(:each) do
      @conn = ActiveRecord::Base.connection
    end

    it "should drop table with :if_exists option no raise error" do
      lambda do
        @conn.drop_table("nonexistent_table", if_exists: true)
      end.should_not raise_error
    end
  end

  describe "rename tables and sequences" do
    before(:each) do
      @conn = ActiveRecord::Base.connection
        schema_define do
          drop_table :test_employees rescue nil
          drop_table :new_test_employees rescue nil
          drop_table :test_employees_no_primary_key rescue nil

          create_table  :test_employees do |t|
            t.string    :first_name
            t.string    :last_name
          end

          create_table  :test_employees_no_pkey, :id => false do |t|
            t.string    :first_name
            t.string    :last_name
          end
        end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees rescue nil
        drop_table :new_test_employees rescue nil
        drop_table :test_employees_no_pkey rescue nil
        drop_table :new_test_employees_no_pkey rescue nil
      end
    end

    it "should rename table name with new one" do
      lambda do
        @conn.rename_table("test_employees","new_test_employees")
      end.should_not raise_error
    end

    it "should raise error when new table name length is too long" do
      lambda do
        @conn.rename_table("test_employees","a"*31)
      end.should raise_error
    end

    it "should not raise error when new sequence name length is too long" do
      lambda do
        @conn.rename_table("test_employees","a"*27)
      end.should_not raise_error
    end

    it "should rename table when table has no primary key and sequence" do
      lambda do
        @conn.rename_table("test_employees_no_pkey","new_test_employees_no_pkey")
      end.should_not raise_error
    end

  end

  describe "create triggers" do

    before(:all) do
      @conn = ActiveRecord::Base.connection
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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
    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

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

  describe "rename index" do
    before(:each) do
      @conn = ActiveRecord::Base.connection
        schema_define do
          create_table  :test_employees do |t|
            t.string    :first_name
            t.string    :last_name
          end
          add_index :test_employees, :first_name
      end
      class ::TestEmployee < ActiveRecord::Base; end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should raise error when current index name and new index name are identical" do
      lambda do
        @conn.rename_index("test_employees","i_test_employees_first_name","i_test_employees_first_name")
      end.should raise_error
    end

    it "should raise error when new index name length is too long" do
      lambda do
        @conn.rename_index("test_employees","i_test_employees_first_name","a"*31)
      end.should raise_error
    end

    it "should raise error when current index name does not exist" do
      lambda do
        @conn.rename_index("test_employees","nonexist_index_name","new_index_name")
      end.should raise_error
    end

    it "should rename index name with new one" do
      lambda do
        @conn.rename_index("test_employees","i_test_employees_first_name","new_index_name")
      end.should_not raise_error
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
    let(:table_name_prefix) { '' }
    let(:table_name_suffix) { '' }

    before(:each) do
      ActiveRecord::Base.table_name_prefix = table_name_prefix
      ActiveRecord::Base.table_name_suffix = table_name_suffix
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
      ActiveRecord::Base.table_name_prefix = ''
      ActiveRecord::Base.table_name_suffix = ''
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should add foreign key" do
      fk_name = "fk_rails_#{Digest::SHA256.hexdigest("test_comments_test_post_id_fk").first(10)}"

      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.#{fk_name}/i}
    end

    context "with table_name_prefix" do
      let(:table_name_prefix) { 'xxx_' }

      it "should use table_name_prefix for foreign table" do
        fk_name = "fk_rails_#{Digest::SHA256.hexdigest("xxx_test_comments_test_post_id_fk").first(10)}"
        schema_define do
          add_foreign_key :test_comments, :test_posts
        end

        lambda do
          TestComment.create(:body => "test", :test_post_id => 1)
        end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.#{fk_name}/i}
      end
    end

    context "with table_name_suffix" do
      let(:table_name_suffix) { '_xxx' }

      it "should use table_name_suffix for foreign table" do
        fk_name = "fk_rails_#{Digest::SHA256.hexdigest("test_comments_xxx_test_post_id_fk").first(10)}"
        schema_define do
          add_foreign_key :test_comments, :test_posts
        end

        lambda do
          TestComment.create(:body => "test", :test_post_id => 1)
        end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.#{fk_name}/i}
      end
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
      end.should raise_error() {|e| e.message.should =~
        /ORA-02291.*\.C#{Digest::SHA1.hexdigest("test_comments_test_post_id_foreign_key")[0,29].upcase}/}
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
      fk_name = "fk_rails_#{Digest::SHA256.hexdigest("test_comments_post_id_fk").first(10)}"

      schema_define do
        add_foreign_key :test_comments, :test_posts, :column => "post_id"
      end
      lambda do
        TestComment.create(:body => "test", :post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.#{fk_name}/i}
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

    it "should add a composite foreign key" do
      pending "Composite foreign keys are not supported in this version"
      schema_define do
        add_column :test_posts, :baz_id, :integer
        add_column :test_posts, :fooz_id, :integer

        execute <<-SQL
          ALTER TABLE TEST_POSTS
          ADD CONSTRAINT UK_FOOZ_BAZ UNIQUE (BAZ_ID,FOOZ_ID)
        SQL

        add_column :test_comments, :baz_id, :integer
        add_column :test_comments, :fooz_id, :integer

        add_foreign_key :test_comments, :test_posts, :columns => ["baz_id", "fooz_id"]
      end

      lambda do
        TestComment.create(:body => "test", :fooz_id => 1, :baz_id => 1)
      end.should raise_error() {|e| e.message.should =~
        /ORA-02291.*\.TES_COM_BAZ_ID_FOO_ID_FK/}
    end

    it "should add a composite foreign key with name" do
      pending "Composite foreign keys are not supported in this version"
      schema_define do
        add_column :test_posts, :baz_id, :integer
        add_column :test_posts, :fooz_id, :integer

        execute <<-SQL
          ALTER TABLE TEST_POSTS
          ADD CONSTRAINT UK_FOOZ_BAZ UNIQUE (BAZ_ID,FOOZ_ID)
        SQL

        add_column :test_comments, :baz_id, :integer
        add_column :test_comments, :fooz_id, :integer

        add_foreign_key :test_comments, :test_posts, :columns => ["baz_id", "fooz_id"], :name => 'comments_posts_baz_fooz_fk'
      end

      lambda do
        TestComment.create(:body => "test", :baz_id => 1, :fooz_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.COMMENTS_POSTS_BAZ_FOOZ_FK/}
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

  describe "lob in table definition" do
    before do
      class ::TestPost < ActiveRecord::Base
      end
    end
    it 'should use default tablespace for clobs' do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = DATABASE_NON_DEFAULT_TABLESPACE
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = nil
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.text :test_clob
          t.binary :test_blob
        end
      end
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_CLOB'").should == DATABASE_NON_DEFAULT_TABLESPACE
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_BLOB'").should_not == DATABASE_NON_DEFAULT_TABLESPACE
    end

    it 'should use default tablespace for blobs' do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = DATABASE_NON_DEFAULT_TABLESPACE
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = nil
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.text :test_clob
          t.binary :test_blob
        end
      end
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_BLOB'").should == DATABASE_NON_DEFAULT_TABLESPACE
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_CLOB'").should_not == DATABASE_NON_DEFAULT_TABLESPACE
    end

    after do
      Object.send(:remove_const, "TestPost")
      schema_define do
        drop_table :test_posts rescue nil
      end
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
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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
    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

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
      @conn = ActiveRecord::Base.connection
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
        self.table_name = "synonym_to_posts"
      end
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define do
        remove_synonym :synonym_to_posts
        remove_synonym :synonym_to_posts_seq
      end
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:clob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:blob)
    end

    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = nil
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:clob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:blob)
    end

    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title, :null => false
          t.string :content
        end
      end
      class ::TestPost < ActiveRecord::Base; end
      TestPost.columns_hash['title'].null.should be_false
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define { drop_table :test_posts }
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
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

    it "should add lob column with non_default tablespace" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_column :test_posts, :body, :text
      end
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'BODY'").should == DATABASE_NON_DEFAULT_TABLESPACE
    end

    it "should add blob column with non_default tablespace" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_column :test_posts, :attachment, :binary
      end
      TestPost.connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'ATTACHMENT'").should == DATABASE_NON_DEFAULT_TABLESPACE
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

    it "should remove column when using change_table" do
      schema_define do
        change_table :test_posts do |t|
          t.remove :title
        end
      end
      TestPost.reset_column_information
      TestPost.columns_hash['title'].should be_nil
    end

    it "should remove multiple columns when using change_table" do
      schema_define do
        change_table :test_posts do |t|
          t.remove :title, :content
        end
      end
      TestPost.reset_column_information
      TestPost.columns_hash['title'].should be_nil
      TestPost.columns_hash['content'].should be_nil
    end

    it "should ignore type and options parameter and remove column" do
      schema_define do
        remove_column :test_posts, :title, :string, {}
      end
      TestPost.reset_column_information
      TestPost.columns_hash['title'].should be_nil
    end
  end

  describe 'virtual columns in create_table' do
    before(:each) do
      pending "Not supported in this database version" unless @oracle11g_or_higher
    end

    it 'should create virtual column with old syntax' do
      schema_define do
        create_table :test_fractions, :force => true do |t|
          t.integer :field1
          t.virtual :field2, :default => 'field1 + 1'
        end
      end
      class ::TestFraction < ActiveRecord::Base
        self.table_name = "test_fractions"
      end

      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.virtual? }
      tf.should_not be nil
      tf.name.should == "field2"
      tf.virtual?.should be true
      lambda do
        tf = TestFraction.new(:field1=>10)
        tf.field2.should be nil # not whatever is in DATA_DEFAULT column
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.field2.to_i.should == 11

      schema_define do
        drop_table :test_fractions
      end
    end

    it 'should raise error if column expression is not provided' do
      lambda {
        schema_define do
          create_table :test_fractions do |t|
            t.integer :field1
            t.virtual :field2
          end
        end
      }.should raise_error
    end
  end

  describe 'virtual columns' do
    before(:each) do
      pending "Not supported in this database version" unless @oracle11g_or_higher
      expr = "( numerator/NULLIF(denominator,0) )*100"
      schema_define do
        create_table :test_fractions, :force => true do |t|
          t.integer :numerator, :default=>0
          t.integer :denominator, :default=>0
          t.virtual :percent, :as => expr
        end
      end
      class ::TestFraction < ActiveRecord::Base
        self.table_name = "test_fractions"
      end
      TestFraction.reset_column_information
    end

    after(:each) do
      if @oracle11g_or_higher
        schema_define do
          drop_table :test_fractions
        end
      end
    end

    it 'should include virtual columns and not try to update them' do
      tf = TestFraction.columns.detect { |c| c.virtual? }
      tf.should_not be nil
      tf.name.should == "percent"
      tf.virtual?.should be true
      lambda do
        tf = TestFraction.new(:numerator=>20, :denominator=>100)
        tf.percent.should be nil # not whatever is in DATA_DEFAULT column
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.percent.to_i.should == 20
    end

    it 'should add virtual column' do
      schema_define do
        add_column :test_fractions, :rem, :virtual, :as => 'remainder(numerator, NULLIF(denominator,0))'
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == 'rem' }
      tf.should_not be nil
      tf.virtual?.should be true
      lambda do
        tf = TestFraction.new(:numerator=>7, :denominator=>5)
        tf.rem.should be nil
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.rem.to_i.should == 2
    end

    it 'should add virtual column with explicit type' do
      schema_define do
        add_column :test_fractions, :expression, :virtual, :as => "TO_CHAR(numerator) || '/' || TO_CHAR(denominator)", :type => :string, :limit => 100
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == 'expression' }
      tf.should_not be nil
      tf.virtual?.should be true
      tf.type.should be :string
      tf.limit.should be 100
      lambda do
        tf = TestFraction.new(:numerator=>7, :denominator=>5)
        tf.expression.should be nil
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.expression.should == '7/5'
    end

    it 'should change virtual column definition' do
      schema_define do
        change_column :test_fractions, :percent, :virtual,
          :as => "ROUND((numerator/NULLIF(denominator,0))*100, 2)", :type => :decimal, :precision => 15, :scale => 2
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == 'percent' }
      tf.should_not be nil
      tf.virtual?.should be true
      tf.type.should be :decimal
      tf.precision.should be 15
      tf.scale.should be 2
      lambda do
        tf = TestFraction.new(:numerator=>11, :denominator=>17)
        tf.percent.should be nil
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.percent.should == '64.71'.to_d
    end

    it 'should change virtual column type' do
      schema_define do
        change_column :test_fractions, :percent, :virtual, :type => :decimal, :precision => 12, :scale => 5
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == 'percent' }
      tf.should_not be nil
      tf.virtual?.should be true
      tf.type.should be :decimal
      tf.precision.should be 12
      tf.scale.should be 5
      lambda do
        tf = TestFraction.new(:numerator=>11, :denominator=>17)
        tf.percent.should be nil
        tf.save!
        tf.reload
      end.should_not raise_error
      tf.percent.should == '64.70588'.to_d
    end
  end

  describe "miscellaneous options" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
    end

    before(:each) do
      @conn.instance_variable_set :@would_execute_sql, @would_execute_sql=''
      class <<@conn
        def execute(sql,name=nil); @would_execute_sql << sql << ";\n"; end
        def index_name_exists?(table_name, index_name, default); default; end
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

    describe "creating a table with a tablespace defaults set" do
      after(:each) do
        @conn.drop_table :tablespace_tests rescue nil
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:table)
      end
      it "should use correct tablespace" do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:table] = DATABASE_NON_DEFAULT_TABLESPACE
        @conn.create_table :tablespace_tests do |t|
          t.string :foo
        end
        @would_execute_sql.should =~ /CREATE +TABLE .* \(.*\) TABLESPACE #{DATABASE_NON_DEFAULT_TABLESPACE}/
      end
    end

    describe "creating an index-organized table" do
      after(:each) do
        @conn.drop_table :tablespace_tests rescue nil
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:table)
      end
      it "should use correct tablespace" do
        @conn.create_table :tablespace_tests, :id=>false, :organization=>'INDEX INITRANS 4 COMPRESS 1', :tablespace=>'bogus' do |t|
          t.integer :id
        end
        @would_execute_sql.should =~ /CREATE +TABLE .*\(.*\)\s+ORGANIZATION INDEX INITRANS 4 COMPRESS 1 TABLESPACE bogus/
      end
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

    it "should use default_tablespaces in add_index" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:index] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_index :keyboards, :name
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:index)
      @would_execute_sql.should =~ /CREATE +INDEX .* ON .* \(.*\) TABLESPACE #{DATABASE_NON_DEFAULT_TABLESPACE}/
    end

    it "should create unique function index but not create unique constraints" do
      schema_define do
        add_index :keyboards, 'lower(name)', unique: true, name: :index_keyboards_on_lower_name
      end
      @would_execute_sql.should_not =~ /ALTER +TABLE .* ADD CONSTRAINT .* UNIQUE \(.*\(.*\)\)/
    end

    describe "#initialize_schema_migrations_table" do
      # In Rails 2.3 to 3.2.x the index name for the migrations
      # table is hard-coded. We can modify the index name here
      # so we can support prefixes/suffixes that would
      # cause the index to be too long.
      #
      # Rails 4 can use this solution as well.
      after(:each) do
        ActiveRecord::Base.table_name_prefix = ''
        ActiveRecord::Base.table_name_suffix = ''
      end

      def add_schema_migrations_index
        schema_define do
          initialize_schema_migrations_table
        end
      end

      context "without prefix or suffix" do
        it "should not truncate the index name" do
          add_schema_migrations_index

          @would_execute_sql.should include('CREATE UNIQUE INDEX "UNIQUE_SCHEMA_MIGRATIONS" ON "SCHEMA_MIGRATIONS" ("VERSION")')
        end
      end

      context "with prefix" do
        before { ActiveRecord::Base.table_name_prefix = 'toolong_' }

        it "should truncate the 'unique_schema_migrations' portion of the index name to fit the prefix within the limit" do
          add_schema_migrations_index

          @would_execute_sql.should include('CREATE UNIQUE INDEX "TOOLONG_UNIQUE_SCHEMA_MIGRATIO" ON "TOOLONG_SCHEMA_MIGRATIONS" ("VERSION")')
        end
      end

      context "with suffix" do
        before { ActiveRecord::Base.table_name_suffix = '_toolong' }

        it "should truncate the 'unique_schema_migrations' portion of the index name to fit the suffix within the limit" do
          add_schema_migrations_index

          @would_execute_sql.should include('CREATE UNIQUE INDEX "UNIQUE_SCHEMA_MIGRATIO_TOOLONG" ON "SCHEMA_MIGRATIONS_TOOLONG" ("VERSION")')
        end
      end

      context "with prefix and suffix" do
        before do
          ActiveRecord::Base.table_name_prefix = 'begin_'
          ActiveRecord::Base.table_name_suffix = '_end'
        end

        it "should truncate the 'unique_schema_migrations' portion of the index name to fit the suffix within the limit" do
          add_schema_migrations_index

          @would_execute_sql.should include('CREATE UNIQUE INDEX "BEGIN_UNIQUE_SCHEMA_MIGRAT_END" ON "BEGIN_SCHEMA_MIGRATIONS_END" ("VERSION")')
        end
      end
    end
  end
end
