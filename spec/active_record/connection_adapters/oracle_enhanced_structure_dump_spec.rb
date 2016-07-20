require 'spec_helper'

describe "OracleEnhancedAdapter structure dump" do
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @oracle11g_or_higher = !! @conn.select_value(
      "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 11")
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
      TestPost.table_name = "test_posts"
    end
  
    after(:each) do
      @conn.drop_table :test_posts 
      @conn.drop_table :foos
      @conn.execute "DROP SEQUENCE test_posts_seq" rescue nil
      @conn.execute "ALTER TABLE test_posts drop CONSTRAINT fk_test_post_foo" rescue nil
      @conn.execute "DROP TRIGGER test_post_trigger" rescue nil
      @conn.execute "DROP TYPE TEST_TYPE" rescue nil
      @conn.execute "DROP TABLE bars" rescue nil
      @conn.execute "ALTER TABLE foos drop CONSTRAINT UK_BAZ" rescue nil
      @conn.execute "ALTER TABLE foos drop CONSTRAINT UK_FOOZ_BAZ" rescue nil
      @conn.execute "ALTER TABLE foos drop column fooz_id" rescue nil
      @conn.execute "ALTER TABLE foos drop column baz_id" rescue nil
      @conn.execute "ALTER TABLE test_posts drop column fooz_id" rescue nil
      @conn.execute "ALTER TABLE test_posts drop column baz_id" rescue nil
      @conn.execute "DROP VIEW test_posts_view_z" rescue nil
      @conn.execute "DROP VIEW test_posts_view_a" rescue nil
    end
  
    it "should dump single primary key" do
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CONSTRAINT (.+) PRIMARY KEY \(ID\)\n/)
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
      expect(dump).to match(/CONSTRAINT (.+) PRIMARY KEY \(ID,TITLE\)\n/)
    end
  
    it "should dump foreign keys" do
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS 
        ADD CONSTRAINT fk_test_post_foo FOREIGN KEY (foo_id) REFERENCES foos(id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      expect(dump.split('\n').length).to eq(1)
      expect(dump).to match(/ALTER TABLE \"?TEST_POSTS\"? ADD CONSTRAINT \"?FK_TEST_POST_FOO\"? FOREIGN KEY \(\"?FOO_ID\"?\) REFERENCES \"?FOOS\"?\(\"?ID\"?\)/i)
    end
    
    it "should dump foreign keys when reference column name is not 'id'" do
      @conn.add_column :foos, :baz_id, :integer
      
      @conn.execute <<-SQL
        ALTER TABLE FOOS 
        ADD CONSTRAINT UK_BAZ UNIQUE (BAZ_ID)
      SQL
      
      @conn.add_column :test_posts, :baz_id, :integer
      
      @conn.execute <<-SQL
        ALTER TABLE TEST_POSTS 
        ADD CONSTRAINT fk_test_post_baz FOREIGN KEY (baz_id) REFERENCES foos(baz_id)
      SQL
      
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      expect(dump.split('\n').length).to eq(1)
      expect(dump).to match(/ALTER TABLE \"?TEST_POSTS\"? ADD CONSTRAINT \"?FK_TEST_POST_BAZ\"? FOREIGN KEY \(\"?BAZ_ID\"?\) REFERENCES \"?FOOS\"?\(\"?BAZ_ID\"?\)/i)
    end
    
    it "should not error when no foreign keys are present" do
      dump = ActiveRecord::Base.connection.structure_dump_fk_constraints
      expect(dump.split('\n').length).to eq(0)
      expect(dump).to eq('')
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
      expect(dump).to match(/CREATE OR REPLACE TRIGGER TEST_POST_TRIGGER/)
    end
  
    it "should dump types" do
      @conn.execute <<-SQL
        create or replace TYPE TEST_TYPE AS TABLE OF VARCHAR2(10);
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      expect(dump).to match(/CREATE OR REPLACE TYPE TEST_TYPE/)
    end

    it "should dump views" do
      @conn.execute "create or replace VIEW test_posts_view_z as select * from test_posts"
      @conn.execute "create or replace VIEW test_posts_view_a as select * from test_posts_view_z"
      dump = ActiveRecord::Base.connection.structure_dump_db_stored_code.gsub(/\n|\s+/,' ')
      expect(dump).to match(/CREATE OR REPLACE FORCE VIEW TEST_POSTS_VIEW_A.*CREATE OR REPLACE FORCE VIEW TEST_POSTS_VIEW_Z/)
    end
  
    it "should dump virtual columns" do
      skip "Not supported in this database version" unless @oracle11g_or_higher
      @conn.execute <<-SQL
        CREATE TABLE bars (
          id          NUMBER(38,0) NOT NULL,
          id_plus     NUMBER GENERATED ALWAYS AS(id + 2) VIRTUAL,
          PRIMARY KEY (ID)
        )
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/\"?ID_PLUS\"? NUMBER GENERATED ALWAYS AS \(ID\+2\) VIRTUAL/)
    end

    it "should dump RAW virtual columns" do
      skip "Not supported in this database version" unless @oracle11g_or_higher
      @conn.execute <<-SQL
        CREATE TABLE bars (
          id          NUMBER(38,0) NOT NULL,
          super       RAW(255) GENERATED ALWAYS AS \( HEXTORAW\(ID\) \) VIRTUAL,
          PRIMARY KEY (ID)
        )
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CREATE TABLE \"BARS\" \(\n\"ID\" NUMBER\(38,0\) NOT NULL,\n \"SUPER\" RAW\(255\) GENERATED ALWAYS AS \(HEXTORAW\(TO_CHAR\(ID\)\)\) VIRTUAL/)
    end

    it "should dump unique keys" do
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      dump = ActiveRecord::Base.connection.structure_dump_unique_keys("test_posts")
      expect(dump).to eq(["ALTER TABLE TEST_POSTS ADD CONSTRAINT UK_FOO_FOO_ID UNIQUE (FOO,FOO_ID)"])
    
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CONSTRAINT UK_FOO_FOO_ID UNIQUE \(FOO,FOO_ID\)/)
    end
  
    it "should dump indexes" do
      ActiveRecord::Base.connection.add_index(:test_posts, :foo, :name => :ix_test_posts_foo)
      ActiveRecord::Base.connection.add_index(:test_posts, :foo_id, :name => :ix_test_posts_foo_id, :unique => true)
      
      @conn.execute <<-SQL
        ALTER TABLE test_posts
          add CONSTRAINT uk_foo_foo_id UNIQUE (foo, foo_id)
      SQL
      
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CREATE UNIQUE INDEX "?IX_TEST_POSTS_FOO_ID"? ON "?TEST_POSTS"? \("?FOO_ID"?\)/i)
      expect(dump).to match(/CREATE  INDEX "?IX_TEST_POSTS_FOO\"? ON "?TEST_POSTS"? \("?FOO"?\)/i)
      expect(dump).not_to match(/CREATE UNIQUE INDEX "?UK_TEST_POSTS_/i)
    end

    it "should dump multi-value and function value indexes" do
      ActiveRecord::Base.connection.add_index(:test_posts, [:foo, :foo_id], :name => :ix_test_posts_foo_foo_id)

      @conn.execute <<-SQL
        CREATE INDEX "IX_TEST_POSTS_FUNCTION" ON "TEST_POSTS" (TO_CHAR(LENGTH("FOO"))||"FOO")
      SQL

      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CREATE  INDEX "?IX_TEST_POSTS_FOO_FOO_ID\"? ON "?TEST_POSTS"? \("?FOO"?, "?FOO_ID"?\)/i)
      expect(dump).to match(/CREATE  INDEX "?IX_TEST_POSTS_FUNCTION\"? ON "?TEST_POSTS"? \(TO_CHAR\(LENGTH\("?FOO"?\)\)\|\|"?FOO"?\)/i)
    end

    it "should dump RAW columns" do
      @conn.execute <<-SQL
        CREATE TABLE bars (
          id          NUMBER(38,0) NOT NULL,
          super       RAW(255),
          PRIMARY KEY (ID)
        )
      SQL
      dump = ActiveRecord::Base.connection.structure_dump
      expect(dump).to match(/CREATE TABLE \"BARS\" \(\n\"ID\" NUMBER\(38,0\) NOT NULL,\n \"SUPER\" RAW\(255\)/)
    end

    it "should dump table comments" do
      comment_sql = %Q(COMMENT ON TABLE "TEST_POSTS" IS 'Test posts with ''some'' "quotes"')
      @conn.execute comment_sql
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /#{comment_sql}/
    end

    it "should dump column comments" do
      comment_sql = %Q(COMMENT ON COLUMN "TEST_POSTS"."TITLE" IS 'The title of the post with ''some'' "quotes"')
      @conn.execute comment_sql
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /#{comment_sql}/
    end

    it "should dump table comments" do
      comment_sql = %Q(COMMENT ON TABLE "TEST_POSTS" IS 'Test posts with ''some'' "quotes"')
      @conn.execute comment_sql
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /#{comment_sql}/
    end

    it "should dump column comments" do
      comment_sql = %Q(COMMENT ON COLUMN "TEST_POSTS"."TITLE" IS 'The title of the post with ''some'' "quotes"')
      @conn.execute comment_sql
      dump = ActiveRecord::Base.connection.structure_dump
      dump.should =~ /#{comment_sql}/
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
      expect(dump).to match(/CREATE GLOBAL TEMPORARY TABLE "?TEST_COMMENTS"?/i)
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
         expect("#$1").to eq("255")
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
      expect(dump).to match(/DROP TABLE "TEMP_TBL"/)
      expect(dump).not_to match(/DROP TABLE "?NOT_TEMP_TBL"?/i)
    end
    after(:each) do
      @conn.drop_table :temp_tbl 
      @conn.drop_table :not_temp_tbl
    end
  end
  
  describe "full drop" do
    before(:each) do 
      @conn.create_table :full_drop_test do |t|
        t.string :foo
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
      expect(drop).to match(/DROP TABLE "FULL_DROP_TEST" CASCADE CONSTRAINTS/)
      expect(drop).to match(/DROP SEQUENCE "FULL_DROP_TEST_SEQ"/)
      expect(drop).to match(/DROP VIEW "FULL_DROP_TEST_VIEW"/)
      expect(drop).not_to match(/DROP TABLE "?FULL_DROP_TEST_MVIEW"?/i)
      expect(drop).to match(/DROP MATERIALIZED VIEW "FULL_DROP_TEST_MVIEW"/)
      expect(drop).to match(/DROP PACKAGE "FULL_DROP_TEST_PACKAGE"/)
      expect(drop).to match(/DROP FUNCTION "FULL_DROP_TEST_FUNCTION"/)
      expect(drop).to match(/DROP PROCEDURE "FULL_DROP_TEST_PROCEDURE"/)
      expect(drop).to match(/DROP SYNONYM "FULL_DROP_TEST_SYNONYM"/)
      expect(drop).to match(/DROP TYPE "FULL_DROP_TEST_TYPE"/)
    end
    it "should not drop tables when preserve_tables is true" do
      drop = @conn.full_drop(true)
      expect(drop).to match(/DROP TABLE "FULL_DROP_TEST_TEMP"/)
      expect(drop).not_to match(/DROP TABLE "?FULL_DROP_TEST"? CASCADE CONSTRAINTS/i)
    end
  end
end
