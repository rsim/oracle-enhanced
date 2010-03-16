require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter structure dump" do
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end
  describe "structure dump" do
    before(:each) do
      @conn.create_table :test_posts, :force => true do |t|
        t.string      :title
        t.string      :foo
        t.integer     :foo_id
      end
      @conn.create_table :foos do |t|
      end
      class ::TestPost < ActiveRecord::Base
      end
      TestPost.set_table_name "test_posts"
    end
  
    after(:each) do
      @conn.drop_table :test_posts 
      @conn.drop_table :foos
      @conn.execute "DROP SEQUENCE test_posts_seq" rescue nil
      @conn.execute "ALTER TABLE test_posts drop CONSTRAINT fk_test_post_foo" rescue nil
      @conn.execute "DROP TRIGGER test_post_trigger" rescue nil
      @conn.execute "DROP TYPE TEST_TYPE" rescue nil
      @conn.execute "DROP TABLE bars" rescue nil
    end
  
    it "should dump single primary key" do
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT (.+) PRIMARY KEY \(ID\)\n/
    end
  
    it "should dump composite primary keys" do
      pk = @conn.send(:select_one, <<-SQL)
        select constraint_name from user_constraints where table_name = 'TEST_POSTS' and constraint_type='P'
      SQL
      @conn.execute <<-SQL
        alter table test_posts drop constraint #{pk["constraint_name"]}
      SQL
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS
        add CONSTRAINT pk_id_title PRIMARY KEY (id, title)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT (.+) PRIMARY KEY \(ID,TITLE\)\n/
    end
  
    it "should dump foreign keys" do
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS 
        ADD CONSTRAINT fk_test_post_foo FOREIGN KEY (foo_id) REFERENCES foos(id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      dump.split('\n').length.should == 1
      dump.should =~ /ALTER TABLE \"?TEST_POSTS\"? ADD CONSTRAINT \"?FK_TEST_POST_FOO\"? FOREIGN KEY \(\"?FOO_ID\"?\) REFERENCES \"?FOOS\"?\(\"?ID\"?\)/i
    end
  
    it "should not error when no foreign keys are present" do
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      dump.split('\n').length.should == 0
      dump.should == ''
    end
  
    it "should dump triggers" do
      @conn.execute <<-SQL
        create or replace TRIGGER TEST_POST_TRIGGER
          BEFORE INSERT
          ON TEST_POSTS
          FOR EACH ROW
        BEGIN
          SELECT 'bar' INTO :new.FOO FROM DUAL;
        END;
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      dump.should =~ /CREATE OR REPLACE TRIGGER TEST_POST_TRIGGER/
    end
  
    it "should dump types" do
      @conn.execute <<-SQL
        create or replace TYPE TEST_TYPE AS TABLE OF VARCHAR2(10);
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      dump.should =~ /CREATE OR REPLACE TYPE TEST_TYPE/
    end
  
    it "should dump virtual columns" do
      pending "Not supported in this database version" unless @conn.select_value("SELECT * FROM v$version WHERE banner LIKE 'Oracle%11g%'")
      @conn.execute <<-SQL
        CREATE TABLE bars (
          id          NUMBER(38,0) NOT NULL,
          id_plus     NUMBER GENERATED ALWAYS AS(id + 2) VIRTUAL,
          PRIMARY KEY (ID)
        )
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /ID_PLUS NUMBER GENERATED ALWAYS AS \(ID\+2\) VIRTUAL/
    end
  
    it "should dump unique keys" do
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_unique_keys("test_posts")
      dump.should == [" CONSTRAINT UK_FOO_FOO_ID UNIQUE (FOO,FOO_ID)"]
    
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CONSTRAINT UK_FOO_FOO_ID UNIQUE \(FOO,FOO_ID\)/
    end
  
    it "should dump indexes" do
      ActiveRecord::Base.connection.add_index(:test_posts, :foo, :name => :ix_test_posts_foo)
      ActiveRecord::Base.connection.add_index(:test_posts, :foo_id, :name => :ix_test_posts_foo_id, :unique => true)
      
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CREATE UNIQUE INDEX "?IX_TEST_POSTS_FOO_ID"? ON "?TEST_POSTS"? \("?FOO_ID"?\)/i
      dump.should =~ /CREATE  INDEX "?IX_TEST_POSTS_FOO\"? ON "?TEST_POSTS"? \("?FOO"?\)/i
      dump.should_not =~ /CREATE UNIQUE INDEX "?UK_TEST_POSTS_/i
    end
  end
  describe "temporary tables" do
    after(:all) do
      @conn.drop_table :test_comments rescue nil
    end
    it "should dump correctly" do
      @conn.create_table :test_comments, :temporary => true, :id => false do |t|
        t.integer :post_id
      end
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /CREATE GLOBAL TEMPORARY TABLE "?TEST_COMMENTS"?/i
    end
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
  
  describe "temp_table_drop" do
    before(:each) do
      @conn.create_table :temp_tbl, :temporary => true do |t|
        t.string :foo
      end
      @conn.create_table :not_temp_tbl do |t|
        t.string :foo
      end
    end
    it "should dump drop sql for just temp tables" do
      dump = @conn.temp_table_drop
      dump.should =~ /DROP TABLE "TEMP_TBL"/
      dump.should_not =~ /DROP TABLE "?NOT_TEMP_TBL"?/i
    end
    after(:each) do
      @conn.drop_table :temp_tbl 
      @conn.drop_table :not_temp_tbl
    end
  end
  
  describe "full drop" do
    before(:each) do 
      @conn.create_table :full_drop_test do |t|
        t.integer :id
      end
      @conn.create_table :full_drop_test_temp, :temporary => true do |t|
        t.string :foo
      end
      #view
      @conn.execute <<-SQL
        create or replace view full_drop_test_view (foo) as select id as "foo" from full_drop_test
      SQL
      #materialized view
      @conn.execute <<-SQL
        create materialized view full_drop_test_mview (foo) as select id as "foo" from full_drop_test
      SQL
      #package
      @conn.execute <<-SQL
        create or replace package full_drop_test_package as
          function test_func return varchar2;
        end test_package;
      SQL
      @conn.execute <<-SQL
        create or replace package body full_drop_test_package as 
          function test_func return varchar2 is
            begin
              return ('foo');
          end test_func;
        end test_package;
      SQL
      #function
      @conn.execute <<-SQL
        create or replace function full_drop_test_function
          return varchar2 
        is
          foo varchar2(3);
        begin 
          return('foo');
        end;
      SQL
      #procedure
      @conn.execute <<-SQL
        create or replace procedure full_drop_test_procedure
        begin
          delete from full_drop_test where id=1231231231
        exception
        when no_data_found then
          dbms_output.put_line('foo');
        end;
      SQL
      #synonym
      @conn.execute <<-SQL
        create or replace synonym full_drop_test_synonym for full_drop_test
      SQL
      #type
      @conn.execute <<-SQL
        create or replace type full_drop_test_type as table of number
      SQL
    end
    after(:each) do
      @conn.drop_table :full_drop_test
      @conn.drop_table :full_drop_test_temp
      @conn.execute "DROP VIEW FULL_DROP_TEST_VIEW" rescue nil
      @conn.execute "DROP MATERIALIZED VIEW FULL_DROP_TEST_MVIEW" rescue nil
      @conn.execute "DROP SYNONYM FULL_DROP_TEST_SYNONYM" rescue nil
      @conn.execute "DROP PACKAGE FULL_DROP_TEST_PACKAGE" rescue nil
      @conn.execute "DROP FUNCTION FULL_DROP_TEST_FUNCTION" rescue nil
      @conn.execute "DROP PROCEDURE FULL_DROP_TEST_PROCEDURE" rescue nil
      @conn.execute "DROP TYPE FULL_DROP_TEST_TYPE" rescue nil
    end
    it "should contain correct sql" do
      drop = @conn.full_drop
      drop.should =~ /DROP TABLE "FULL_DROP_TEST" CASCADE CONSTRAINTS/
      drop.should =~ /DROP SEQUENCE "FULL_DROP_TEST_SEQ"/
      drop.should =~ /DROP VIEW "FULL_DROP_TEST_VIEW"/
      drop.should_not =~ /DROP TABLE "?FULL_DROP_TEST_MVIEW"?/i
      drop.should =~ /DROP MATERIALIZED VIEW "FULL_DROP_TEST_MVIEW"/
      drop.should =~ /DROP PACKAGE "FULL_DROP_TEST_PACKAGE"/
      drop.should =~ /DROP FUNCTION "FULL_DROP_TEST_FUNCTION"/
      drop.should =~ /DROP PROCEDURE "FULL_DROP_TEST_PROCEDURE"/
      drop.should =~ /DROP SYNONYM "FULL_DROP_TEST_SYNONYM"/
      drop.should =~ /DROP TYPE "FULL_DROP_TEST_TYPE"/
    end
    it "should not drop tables when preserve_tables is true" do
      drop = @conn.full_drop(true)
      drop.should =~ /DROP TABLE "FULL_DROP_TEST_TEMP"/
      drop.should_not =~ /DROP TABLE "?FULL_DROP_TEST"? CASCADE CONSTRAINTS/i
    end
  end
end