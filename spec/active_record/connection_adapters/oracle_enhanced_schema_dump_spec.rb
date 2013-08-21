require 'spec_helper'

describe "OracleEnhancedAdapter schema dump" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @oracle11g = !! @conn.select_value("SELECT * FROM v$version WHERE banner LIKE 'Oracle%11g%'")
  end

  def standard_dump(options = {})
    stream = StringIO.new
    ActiveRecord::SchemaDumper.ignore_tables = options[:ignore_tables]||[]
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
    stream.string
  end

  def create_test_posts_table(options = {})
    options.merge! :force => true
    schema_define do
      create_table :test_posts, options do |t|
        t.string :title
        t.timestamps
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

  describe "tables" do
    after(:each) do
      drop_test_posts_table
    end

    it "should not include ignored table names in schema dump" do
      create_test_posts_table
      standard_dump(:ignore_tables => %w(test_posts)).should_not =~ /create_table "test_posts"/
    end

    it "should not include ignored table regexes in schema dump" do
      create_test_posts_table
      standard_dump(:ignore_tables => [ /test_posts/i ]).should_not =~ /create_table "test_posts"/
    end

    it "should create a standard primary key" do
      create_test_posts_table
      standard_dump.should_not =~ /create_table "test_posts", :id => false/
    end

  end

  describe "dumping default values" do
    before :each do
      schema_define do
        create_table "test_defaults", :force => true do |t|
          t.string "regular", :default => "c"
          t.string "special_c", :default => "\n"
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table "test_defaults"
      end
    end

    it "should be able to dump default values using special characters" do
      standard_dump.should =~ /t.string \"special_c\", :default => "\\n"/
    end
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

    it "should remove table prefix with $ sign in schema dump" do
      ActiveRecord::Base.table_name_prefix = 'xxx$'
      create_test_posts_table
      standard_dump.should =~ /create_table "test_posts".*add_index "test_posts"/m
    end

    it "should remove table suffix in schema dump" do
      ActiveRecord::Base.table_name_suffix = '_xxx'
      create_test_posts_table
      standard_dump.should =~ /create_table "test_posts".*add_index "test_posts"/m
    end

    it "should remove table suffix with $ sign in schema dump" do
      ActiveRecord::Base.table_name_suffix = '$xxx'
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

    it "should not include alter table statement" do
      create_test_posts_table(:primary_key => 'post_id')
      standard_dump.should_not =~ /ALTER TABLE test_posts ADD PRIMARY KEY \(post_id\)/
    end

  end

  describe "table with non-default primary key with non-numeric data type" do

    before(:all) do
      schema_define do
        create_table :test_posts, :id => false, :force => true do |t|
          t.string :guid_key
          t.string :title
        end
        execute "ALTER TABLE test_posts ADD PRIMARY KEY (guid_key)"
      end
    end

    after(:each) do
      drop_test_posts_table
    end

    it "should include alter table for primary key" do
      standard_dump.should =~ /create_table "test_posts", :id => false/
      standard_dump.should =~ /t.string "guid_key"/
      standard_dump.should =~ /execute "ALTER TABLE test_posts ADD PRIMARY KEY \(guid_key\)"/
    end

  end

  describe "table with composite primary key" do

    before(:all) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
        create_table :test_keywords, :force => true do |t|
          t.string :name
        end

        create_table :test_posts_keywords, :id => false, :force => true do |t|
          t.integer :posts_id
          t.integer :keywords_id
        end
        execute "ALTER TABLE test_posts_keywords ADD PRIMARY KEY (posts_id, keywords_id)"
      end
    end

    after(:each) do
      drop_table :test_posts rescue nil
      drop_table :test_keywords rescue nil
    end

    it "should generate a composite primary key in schema dump" do
      standard_dump.should =~ /create_table "test_posts_keywords", :id => false/
      standard_dump.should =~ /t.integer "posts_id"/
      standard_dump.should =~ /t.integer "keywords_id"/
      standard_dump.should =~ /execute "ALTER TABLE test_posts_keywords ADD PRIMARY KEY \(posts_id, keywords_id\)"/
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
        remove_foreign_key :test_comments, :test_posts rescue nil
        remove_foreign_key :test_comments, :name => 'comments_posts_baz_fooz_fk' rescue nil
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

    it "should not include foreign keys on ignored table names in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      standard_dump(:ignore_tables => %w(test_comments)).should_not =~ /add_foreign_key "test_comments"/
    end

    it "should not include foreign keys on ignored table regexes in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      standard_dump(:ignore_tables => [ /test_comments/i ]).should_not =~ /add_foreign_key "test_comments"/
    end

    it "should include foreign keys referencing ignored table names in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      standard_dump(:ignore_tables => %w(test_posts)).should =~ /add_foreign_key "test_comments"/
    end

    it "should include foreign keys referencing ignored table regexes in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      standard_dump(:ignore_tables => [ /test_posts/i ]).should =~ /add_foreign_key "test_comments"/
    end

    it "should include composite foreign keys" do
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
      standard_dump.should =~ /add_foreign_key "test_comments", "test_posts", :columns => \["baz_id", "fooz_id"\], :name => "comments_posts_baz_fooz_fk"/
    end
    it "should include foreign keys following all tables" do
      # if foreign keys preceed declaration of all tables
      # it can cause problems when using db:test rake tasks
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      dump = standard_dump
      dump.rindex("create_table").should < dump.index("add_foreign_key")
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
      standard_dump.should =~ /add_synonym "test_synonym", "table_name@link_name(\.[-A-Za-z0-9_]+)*", :force => true/
    end

    it "should not include ignored table names in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", :force => true
      end
      standard_dump(:ignore_tables => %w(test_synonym)).should_not =~ /add_synonym "test_synonym"/
    end

    it "should not include ignored table regexes in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", :force => true
      end
      standard_dump(:ignore_tables => [ /test_synonym/i ]).should_not =~ /add_synonym "test_synonym"/
    end

    it "should include synonyms to ignored table regexes in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", :force => true
      end
      standard_dump(:ignore_tables => [ /table_name/i ]).should =~ /add_synonym "test_synonym"/
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
      standard_dump.should =~ /add_index "test_posts", \["title"\], :name => "index_test_posts_on_title"$/
    end

    it "should specify non-default tablespace in add index" do
      tablespace_name = @conn.default_tablespace
      @conn.stub!(:default_tablespace).and_return('dummy')
      create_test_posts_table
      standard_dump.should =~ /add_index "test_posts", \["title"\], :name => "index_test_posts_on_title", :tablespace => "#{tablespace_name}"$/
    end

    it "should create and dump function-based indexes" do
      create_test_posts_table
      @conn.add_index :test_posts, "NVL(created_at, updated_at)", :name => "index_test_posts_cr_upd_at"
      standard_dump.should =~ /add_index "test_posts", \["NVL\(\\"CREATED_AT\\",\\"UPDATED_AT\\"\)"\], :name => "index_test_posts_cr_upd_at"$/
    end

  end

  describe "materialized views" do
    after(:each) do
      @conn.execute "DROP MATERIALIZED VIEW test_posts_mv" rescue nil
      drop_test_posts_table
    end

    it "should not include materialized views in schema dump" do
      create_test_posts_table
      @conn.execute "CREATE MATERIALIZED VIEW test_posts_mv AS SELECT * FROM test_posts"
      standard_dump.should_not =~ /create_table "test_posts_mv"/
    end
  end

  describe 'virtual columns' do
    before(:all) do
      if @oracle11g
        schema_define do
          create_table :test_names, :force => true do |t|
            t.string  :first_name
            t.string  :last_name
            t.virtual :full_name,        :as => "first_name || ', ' || last_name"
            t.virtual :short_name,       :as => "COALESCE(first_name, last_name)", :type => :string, :limit => 300
            t.virtual :abbrev_name,      :as => "SUBSTR(first_name,1,50) || ' ' || SUBSTR(last_name,1,1) || '.'", :type => "VARCHAR(100)"
            t.virtual :name_ratio, :as=>'(LENGTH(first_name)*10/LENGTH(last_name)*10)'
            t.column  :full_name_length, :virtual, :as => "length(first_name || ', ' || last_name)", :type => :integer
            t.virtual :field_with_leading_space, :as => "' ' || first_name || ' '", :limit => 300, :type => :string
          end
        end
      else
        pending "Not supported in this database version"
      end
    end

    before(:each) do
      if @oracle11g
        class ::TestName < ActiveRecord::Base
          if self.respond_to?(:table_name=)
            self.table_name = "test_names"
          else
            set_table_name "test_names"
          end
        end
      end
    end

    after(:all) do
      if @oracle11g
        schema_define do
          drop_table :test_names
        end
      end
    end

    it 'should dump correctly' do
      standard_dump.should =~ /t\.virtual "full_name",(\s*):limit => 512,(\s*):as => "\\"FIRST_NAME\\"\|\|', '\|\|\\"LAST_NAME\\"",(\s*):type => :string/
      standard_dump.should =~ /t\.virtual "short_name",(\s*):limit => 300,(\s*):as =>(.*),(\s*):type => :string/
      standard_dump.should =~ /t\.virtual "full_name_length",(\s*):precision => 38,(\s*):scale => 0,(\s*):as =>(.*),(\s*):type => :integer/
      standard_dump.should =~ /t\.virtual "name_ratio",(\s*):as =>(.*)\"$/ # no :type
      standard_dump.should =~ /t\.virtual "abbrev_name",(\s*):limit => 100,(\s*):as =>(.*),(\s*):type => :string/
      standard_dump.should =~ /t\.virtual "field_with_leading_space",(\s*):limit => 300,(\s*):as => "' '\|\|\\"FIRST_NAME\\"\|\|' '",(\s*):type => :string/
    end

    context 'with column cache' do
      before(:all) do
        @old_cache = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true
      end
      after(:all) do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = @old_cache
      end
      it 'should not change column defaults after several dumps' do
        col = TestName.columns.detect{|c| c.name == 'full_name'}
        col.should_not be_nil
        col.virtual_column_data_default.should_not =~ /:as/

        standard_dump
        col.virtual_column_data_default.should_not =~ /:as/

        standard_dump
        col.virtual_column_data_default.should_not =~ /:as/
      end
    end

    context "with index on virtual column" do
      before(:all) do
        if @oracle11g
          schema_define do 
            add_index 'test_names', 'field_with_leading_space', :name => "index_on_virtual_col"
          end
        end
      end
      after(:all) do
        if @oracle11g
          schema_define do
            remove_index 'test_names', :name => 'index_on_virtual_col'
          end
        end
      end
      it 'should dump correctly' do
        standard_dump.should_not =~ /add_index "test_names".+FIRST_NAME.+$/
        standard_dump.should     =~ /add_index "test_names".+field_with_leading_space.+$/
      end
    end
  end

end
