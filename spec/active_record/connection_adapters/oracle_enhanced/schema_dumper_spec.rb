# frozen_string_literal: true

describe "OracleEnhancedAdapter schema dump" do
  include SchemaSpecHelper
  include SchemaDumpingHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @oracle11g_or_higher = !! @conn.select_value(
      "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 11")
  end

  def standard_dump(options = {})
    stream = StringIO.new
    ActiveRecord::SchemaDumper.ignore_tables = options[:ignore_tables] || []
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    stream.string
  end

  def create_test_posts_table(options = {})
    options[:force] = true
    schema_define do
      create_table :test_posts, **options do |t|
        t.string :title
        t.timestamps null: true
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
      expect(standard_dump(ignore_tables: %w(test_posts))).not_to match(/create_table "test_posts"/)
    end

    it "should not include ignored table regexes in schema dump" do
      create_test_posts_table
      expect(standard_dump(ignore_tables: [ /test_posts/i ])).not_to match(/create_table "test_posts"/)
    end
  end

  describe "dumping default values" do
    before :each do
      schema_define do
        create_table "test_defaults", force: true do |t|
          t.string "regular", default: "c"
          t.string "special_c", default: "\n"
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table "test_defaults"
      end
    end

    it "should be able to dump default values using special characters" do
      output = dump_table_schema "test_defaults"
      expect(output).to match(/t.string "special_c", default: "\\n"/)
    end
  end

  describe "table with non-default primary key" do
    after(:each) do
      drop_test_posts_table
    end

    it "should include non-default primary key in schema dump" do
      create_test_posts_table(primary_key: "post_id")
      output = dump_table_schema "test_posts"
      expect(output).to match(/create_table "test_posts", primary_key: "post_id"/)
    end
  end

  describe "table with ntext columns" do
    before :each do
      schema_define do
        create_table "test_ntexts", force: true do |t|
          t.ntext :ntext_column
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table "test_ntexts"
      end
    end

    it "should be able to dump ntext columns" do
      output = dump_table_schema "test_ntexts"
      expect(output).to match(/t.ntext "ntext_column"/)
    end
  end

  describe "foreign key constraints" do
    before(:all) do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post
        end
      end
    end

    after(:each) do
      schema_define do
        remove_foreign_key :test_comments, :test_posts rescue nil
        remove_foreign_key :test_comments, name: "comments_posts_baz_fooz_fk" rescue nil
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
      end
    end

    it "should include foreign key in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts"/)
    end

    it "should include foreign key with delete dependency in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, on_delete: :cascade
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts", on_delete: :cascade/)
    end

    it "should include foreign key with nullify dependency in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, on_delete: :nullify
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts", on_delete: :nullify/)
    end

    it "should not include foreign keys on ignored table names in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect(standard_dump(ignore_tables: %w(test_comments))).not_to match(/add_foreign_key "test_comments"/)
    end

    it "should not include foreign keys on ignored table regexes in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect(standard_dump(ignore_tables: [ /test_comments/i ])).not_to match(/add_foreign_key "test_comments"/)
    end

    it "should include foreign keys referencing ignored table names in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect(standard_dump(ignore_tables: %w(test_posts))).to match(/add_foreign_key "test_comments"/)
    end

    it "should include foreign keys referencing ignored table regexes in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect(standard_dump(ignore_tables: [ /test_posts/i ])).to match(/add_foreign_key "test_comments"/)
    end

    it "should include foreign keys following all tables" do
      # if foreign keys precede declaration of all tables
      # it can cause problems when using db:test rake tasks
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      dump = standard_dump
      expect(dump.rindex("create_table")).to be < dump.index("add_foreign_key")
    end

    it "should include primary_key when reference column name is not 'id'" do
      schema_define do
        create_table :test_posts, force: true, primary_key: "baz_id" do |t|
          t.string :title
        end
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.integer :baz_id
        end
      end

      @conn.execute <<~SQL
        ALTER TABLE TEST_COMMENTS
        ADD CONSTRAINT TEST_COMMENTS_BAZ_ID_FK FOREIGN KEY (baz_id) REFERENCES test_posts(baz_id)
      SQL

      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts", column: "baz_id", primary_key: "baz_id", name: "test_comments_baz_id_fk"/)
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
        add_synonym :test_synonym, "schema_name.table_name", force: true
      end
      expect(standard_dump).to match(/add_synonym "test_synonym", "schema_name.table_name", force: true/)
    end

    it "should not include ignored table names in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", force: true
      end
      expect(standard_dump(ignore_tables: %w(test_synonym))).not_to match(/add_synonym "test_synonym"/)
    end

    it "should not include ignored table regexes in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", force: true
      end
      expect(standard_dump(ignore_tables: [ /test_synonym/i ])).not_to match(/add_synonym "test_synonym"/)
    end

    it "should include synonyms to ignored table regexes in schema dump" do
      schema_define do
        add_synonym :test_synonym, "schema_name.table_name", force: true
      end
      expect(standard_dump(ignore_tables: [ /table_name/i ])).to match(/add_synonym "test_synonym"/)
    end
  end

  describe "temporary tables" do
    after(:each) do
      drop_test_posts_table
    end

    it "should include temporary options" do
      create_test_posts_table(temporary: true)
      output = dump_table_schema "test_posts"
      expect(output).to match(/create_table "test_posts", temporary: true/)
    end
  end

  describe "indexes" do
    after(:each) do
      drop_test_posts_table
    end

    it "should not specify default tablespace in add index" do
      create_test_posts_table
      output = dump_table_schema "test_posts"
      expect(output).to match(/t\.index \["title"\], name: "index_test_posts_on_title"$/)
    end

    it "should specify non-default tablespace in add index" do
      tablespace_name = @conn.default_tablespace
      allow(@conn).to receive(:default_tablespace).and_return("dummy")
      create_test_posts_table
      output = dump_table_schema "test_posts"
      expect(output).to match(/t\.index \["title"\], name: "index_test_posts_on_title", tablespace: "#{tablespace_name}"$/)
    end

    it "should create and dump function-based indexes" do
      create_test_posts_table
      @conn.add_index :test_posts, "NVL(created_at, updated_at)", name: "index_test_posts_cr_upd_at"
      output = dump_table_schema "test_posts"
      expect(output).to match(/t\.index \["NVL\(\\"CREATED_AT\\",\\"UPDATED_AT\\"\)"\], name: "index_test_posts_cr_upd_at"$/)
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
      expect(standard_dump).not_to match(/create_table "test_posts_mv"/)
    end
  end

  describe "context indexes" do
    before(:each) do
      schema_define do
        create_table :test_context_indexed_posts, force: true do |t|
          t.string :title
          t.string :body
          t.index :title
        end
        add_context_index :test_context_indexed_posts, :body, sync: "ON COMMIT"
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_context_indexed_posts
      end
    end

    it "should dump the context index" do
      expect(standard_dump).to include(%(add_context_index "test_context_indexed_posts", ["body"]))
    end

    it "dumps the sync option" do
      expect(standard_dump).to include(%(sync: "ON COMMIT"))
    end
  end

  describe "virtual columns" do
    before(:all) do
      skip "Not supported in this database version" unless @oracle11g_or_higher
      schema_define do
        create_table :test_names, force: true do |t|
          t.string :first_name
          t.string :last_name
          t.virtual :full_name,       as: "first_name || ', ' || last_name"
          t.virtual :short_name,      as: "COALESCE(first_name, last_name)", type: :string, limit: 300
          t.virtual :abbrev_name,     as: "SUBSTR(first_name,1,50) || ' ' || SUBSTR(last_name,1,1) || '.'", type: "VARCHAR(100)"
          t.virtual :name_ratio,      as: "(LENGTH(first_name)*10/LENGTH(last_name)*10)"
          t.column :full_name_length, :virtual, as: "length(first_name || ', ' || last_name)", type: :integer
          t.virtual :field_with_leading_space, as: "' ' || first_name || ' '", limit: 300, type: :string
        end
      end
    end

    before(:each) do
      if @oracle11g_or_higher
        class ::TestName < ActiveRecord::Base
          self.table_name = "test_names"
        end
      end
    end

    after(:all) do
      if @oracle11g_or_higher
        schema_define do
          drop_table :test_names
        end
      end
    end

    it "should dump correctly" do
      output = dump_table_schema "test_names"
      expect(output).to match(/t\.virtual "full_name",(\s*)type: :string,(\s*)limit: 512,(\s*)as: "\\"FIRST_NAME\\"\|\|', '\|\|\\"LAST_NAME\\""/)
      expect(output).to match(/t\.virtual "short_name",(\s*)type: :string,(\s*)limit: 300,(\s*)as:(.*)/)
      expect(output).to match(/t\.virtual "full_name_length",(\s*)type: :integer,(\s*)precision: 38,(\s*)as:(.*)/)
      expect(output).to match(/t\.virtual "name_ratio",(\s*)as:(.*)"$/) # no :type
      expect(output).to match(/t\.virtual "abbrev_name",(\s*)type: :string,(\s*)limit: 100,(\s*)as:(.*)/)
      expect(output).to match(/t\.virtual "field_with_leading_space",(\s*)type: :string,(\s*)limit: 300,(\s*)as: "' '\|\|\\"FIRST_NAME\\"\|\|' '"/)
    end

    context "with index on virtual column" do
      before(:all) do
        if @oracle11g_or_higher
          schema_define do
            add_index "test_names", "field_with_leading_space", name: "index_on_virtual_col"
          end
        end
      end

      after(:all) do
        if @oracle11g_or_higher
          schema_define do
            remove_index "test_names", name: "index_on_virtual_col"
          end
        end
      end

      it "should dump correctly" do
        output = dump_table_schema "test_names"
        expect(output).not_to match(/t\.index .+FIRST_NAME.+$/)
        expect(output).to     match(/t\.index .+field_with_leading_space.+$/)
      end
    end
  end

  describe ":float datatype" do
    before(:each) do
      schema_define do
        create_table :test_floats, force: true do |t|
          t.float :hourly_rate
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_floats
      end
    end

    it "should dump float type correctly" do
      output = dump_table_schema "test_floats"
      expect(output).to match(/t\.float "hourly_rate"$/)
    end
  end

  describe "table comments" do
    before(:each) do
      schema_define do
        create_table :test_table_comments, comment: "this is a \"table comment\"!", force: true do |t|
          t.string :blah
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_table_comments
      end
    end

    it "should dump table comments" do
      output = dump_table_schema "test_table_comments"
      expect(output).to match(/create_table "test_table_comments", comment: "this is a \\"table comment\\"!", force: :cascade do \|t\|$/)
    end
  end

  describe "column comments" do
    before(:each) do
      schema_define do
        create_table :test_column_comments, force: true do |t|
          t.string :blah, comment: "this is a \"column comment\"!"
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_column_comments
      end
    end

    it "should dump column comments" do
      output = dump_table_schema "test_column_comments"
      expect(output).to match(/comment: "this is a \\"column comment\\"!"/)
    end
  end

  describe "schema.rb format" do
    before do
      create_test_posts_table

      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :title
        end

        add_index :test_comments, :title
      end
    end

    it "should be only one blank line between create_table methods in schema dump" do
      expect(standard_dump).to match(/end\n\n  create_table/)
    end

    after do
      schema_define do
        drop_table :test_comments, if_exists: true
      end

      drop_test_posts_table
    end
  end
end
