require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

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
      @conn.clear_prefetch_primary_key
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

  describe "temporary tables" do
    after(:each) do
      drop_test_posts_table
    end
    
    it "should include temporary options" do
      create_test_posts_table(:temporary => true)
      standard_dump.should =~ /create_table "test_posts", :temporary => true/
    end
  end

  describe "indexes" do
    after(:each) do
      drop_test_posts_table
    end

    it "should not specify default tablespace in add index" do
      create_test_posts_table
      standard_dump.should =~ /add_index \"test_posts\", \[\"title\"\], :name => \"index_test_posts_on_title\"$/
    end

    it "should not specify default tablespace in add index" do
      tablespace_name = @conn.default_tablespace
      @conn.stub!(:default_tablespace).and_return('dummy')
      create_test_posts_table
      standard_dump.should =~ /add_index \"test_posts\", \[\"title\"\], :name => \"index_test_posts_on_title\", :tablespace => \"#{tablespace_name}\"$/
    end

  end

end

