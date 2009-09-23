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

  describe "table prefixes and suffixes" do
    after(:each) do
      drop_test_posts_table
      @conn.drop_table(ActiveRecord::Migrator.schema_migrations_table_name) if @conn.table_exists?(ActiveRecord::Migrator.schema_migrations_table_name)
      ActiveRecord::Base.table_name_prefix = ''
      ActiveRecord::Base.table_name_suffix = ''
    end

    def create_test_posts_table
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table :test_posts, :force => true do |t|
            t.string :title
          end
          add_index :test_posts, :title
        end
      end
    end
    
    def drop_test_posts_table
      ActiveRecord::Schema.define do
        suppress_messages do
          drop_table :test_posts
        end
      end
    rescue
      nil
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
