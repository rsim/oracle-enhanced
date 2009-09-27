require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter original schema dump" do

  before(:all) do
    if !defined?(RUBY_ENGINE)
      if ActiveRecord::Base.respond_to?(:oracle_connection)
        @old_conn = ActiveRecord::Base.oracle_connection(CONNECTION_PARAMS)
        @old_conn.class.should == ActiveRecord::ConnectionAdapters::OracleAdapter
      end
    elsif RUBY_ENGINE == 'jruby'
      @old_conn = ActiveRecord::Base.jdbc_connection(JDBC_CONNECTION_PARAMS)
      @old_conn.class.should == ActiveRecord::ConnectionAdapters::JdbcAdapter
    end

    @new_conn = ActiveRecord::Base.oracle_enhanced_connection(CONNECTION_PARAMS)
    @new_conn.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  after(:all) do
    # Workaround for undefining callback that was defined by JDBC adapter
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
      ActiveRecord::Base.class_eval do
        def after_save_with_oracle_lob
          nil
        end
      end
    end
  end

  if !defined?(RUBY_ENGINE) && ActiveRecord::Base.respond_to?(:oracle_connection) || defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
    it "should return the same tables list as original oracle adapter" do
      @new_conn.tables.sort.should == @old_conn.tables.sort
    end

    it "should return the same index list as original oracle adapter" do
      @new_conn.indexes('employees').sort_by(&:name).should == @old_conn.indexes('employees').sort_by(&:name)
    end

    it "should return the same pk_and_sequence_for as original oracle adapter" do
      if @old_conn.respond_to?(:pk_and_sequence_for)
        @new_conn.tables.each do |t|
          @new_conn.pk_and_sequence_for(t).should == @old_conn.pk_and_sequence_for(t)
        end
      end
    end

    it "should return the same structure dump as original oracle adapter" do
      @new_conn.structure_dump.split(";\n\n").sort.should == @old_conn.structure_dump.split(";\n\n").sort
    end

    it "should return the same structure drop as original oracle adapter" do
      @new_conn.structure_drop.split(";\n\n").sort.should == @old_conn.structure_drop.split(";\n\n").sort
    end
  end

end

describe "OracleEnhancedAdapter schema dump" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  def standard_dump
    stream = StringIO.new
    ActiveRecord::SchemaDumper.ignore_tables = []
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
    stream.string
  end

  def create_test_posts_table(options = {})
    options.merge! :force => true
    schema_define do
      create_table :test_posts, options do |t|
        t.string :title
      end
      add_index :test_posts, :title
    end
  end

  def drop_test_posts_table
    schema_define do
      drop_table :test_posts
    end
  rescue
    nil
  end

  describe "table prefixes and suffixes" do
    after(:each) do
      drop_test_posts_table
      @conn.drop_table(ActiveRecord::Migrator.schema_migrations_table_name) if @conn.table_exists?(ActiveRecord::Migrator.schema_migrations_table_name)
      ActiveRecord::Base.table_name_prefix = ''
      ActiveRecord::Base.table_name_suffix = ''
    end

    it "should remove table prefix in schema dump" do
      ActiveRecord::Base.table_name_prefix = 'xxx_'
      create_test_posts_table
      standard_dump.should =~ /create_table "test_posts".*add_index "test_posts"/m
    end

    it "should remove table suffix in schema dump" do
      ActiveRecord::Base.table_name_suffix = '_xxx'
      create_test_posts_table
      standard_dump.should =~ /create_table "test_posts".*add_index "test_posts"/m
    end

    it "should not include schema_migrations table with prefix in schema dump" do
      ActiveRecord::Base.table_name_prefix = 'xxx_'
      @conn.initialize_schema_migrations_table
      standard_dump.should_not =~ /schema_migrations/
    end

    it "should not include schema_migrations table with suffix in schema dump" do
      ActiveRecord::Base.table_name_suffix = '_xxx'
      @conn.initialize_schema_migrations_table
      standard_dump.should_not =~ /schema_migrations/
    end

  end

  describe "table with non-default primary key" do
    after(:each) do
      drop_test_posts_table
    end

    it "should include non-default primary key in schema dump" do
      create_test_posts_table(:primary_key => 'post_id')
      standard_dump.should =~ /create_table "test_posts", :primary_key => "post_id"/
    end

  end

  describe "table with primary key trigger" do

    after(:each) do
      drop_test_posts_table
    end

    it "should include primary key trigger in schema dump" do
      create_test_posts_table(:primary_key_trigger => true)
      standard_dump.should =~ /create_table "test_posts".*add_primary_key_trigger "test_posts"/m
    end

    it "should include primary key trigger with non-default primary key in schema dump" do
      create_test_posts_table(:primary_key_trigger => true, :primary_key => 'post_id')
      standard_dump.should =~ /create_table "test_posts", :primary_key => "post_id".*add_primary_key_trigger "test_posts", :primary_key => "post_id"/m
    end

  end

  describe "foreign key constraints" do
    before(:all) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
        end
      end
    end
    
    after(:each) do
      schema_define do
        remove_foreign_key :test_comments, :test_posts
      end
    end
    after(:all) do
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should include foreign key in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      standard_dump.should =~ /add_foreign_key "test_comments", "test_posts", :name => "test_comments_test_post_id_fk"/
    end

    it "should include foreign key with delete dependency in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :delete
      end
      standard_dump.should =~ /add_foreign_key "test_comments", "test_posts", :name => "test_comments_test_post_id_fk", :dependent => :delete/
    end

    it "should include foreign key with nullify dependency in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :nullify
      end
      standard_dump.should =~ /add_foreign_key "test_comments", "test_posts", :name => "test_comments_test_post_id_fk", :dependent => :nullify/
    end

  end

  describe "synonyms" do
    after(:each) do
      schema_define do
        remove_synonym :test_synonym
      end
    end

    it "should include synonym to other schema table in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", :force => true
      end
      standard_dump.should =~ /add_synonym "test_synonym", "schema_name.table_name", :force => true/
    end

    it "should include synonym to other database table in schema dump" do
      schema_define do
        add_synonym :test_synonym, "table_name@link_name", :force => true
      end
      standard_dump.should =~ /add_synonym "test_synonym", "table_name@link_name", :force => true/
    end

  end

end

describe "OracleEnhancedAdapter structure dump" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "database stucture dump extentions" do
    before(:all) do
      @conn.execute <<-SQL
        CREATE TABLE nvarchartable (
          unq_nvarchar  NVARCHAR2(255) DEFAULT NULL
        )
      SQL
    end

    after(:all) do
      @conn.execute "DROP TABLE nvarchartable"
    end

    it "should return the character size of nvarchar fields" do
      if /.*unq_nvarchar nvarchar2\((\d+)\).*/ =~ @conn.structure_dump
         "#$1".should == "255"
      end
    end
  end

end
