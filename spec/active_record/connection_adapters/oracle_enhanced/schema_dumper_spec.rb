# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter schema dump" do
  include SchemaSpecHelper
  include SchemaDumpingHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
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

  describe "expression index" do
    before(:each) do
      schema_define do
        create_table :test_idx_expr_dump, force: true do |t|
          t.string :name
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_idx_expr_dump, if_exists: true
      end
    end

    it "dumps a function-based index with the expression preserved" do
      schema_define do
        add_index :test_idx_expr_dump, "LOWER(name)", name: "ix_dump_expr"
      end
      output = dump_table_schema "test_idx_expr_dump"
      expect(output).to match(/t\.index \[.*LOWER\(.*NAME.*\).*\], name: "ix_dump_expr"/im)
    end

    it "round-trips an expression index through dump and load" do
      schema_define do
        add_index :test_idx_expr_dump, "LOWER(name)", name: "ix_rt_expr"
      end
      dumped = dump_table_schema "test_idx_expr_dump"
      schema_define do
        drop_table :test_idx_expr_dump, if_exists: true
      end
      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }
      expr = ActiveRecord::Base.lease_connection.select_value(<<~SQL.squish)
        SELECT column_expression FROM all_ind_expressions
         WHERE index_owner = SYS_CONTEXT('userenv', 'current_schema')
           AND index_name = 'IX_RT_EXPR'
      SQL
      expect(expr).to match(/LOWER\("?NAME"?\)/i)
    end
  end

  describe "index sort order" do
    before(:each) do
      schema_define do
        create_table :test_idx_sort_dump, force: true do |t|
          t.string :first_name
          t.string :last_name
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_idx_sort_dump, if_exists: true
      end
    end

    it "dumps order: { col: :desc } for descending indexes" do
      schema_define do
        add_index :test_idx_sort_dump, [:first_name, :last_name],
                  name: "ix_dump_sort", order: { last_name: :desc }
      end
      output = dump_table_schema "test_idx_sort_dump"
      expect(output).to match(/t\.index \[.*first_name.*last_name.*\], name: "ix_dump_sort", order: \{ last_name: :desc \}/im)
    end

    it "round-trips a DESC index through dump and load" do
      schema_define do
        add_index :test_idx_sort_dump, [:first_name, :last_name],
                  name: "ix_rt_sort", order: { last_name: :desc }
      end
      dumped = dump_table_schema "test_idx_sort_dump"
      schema_define do
        drop_table :test_idx_sort_dump, if_exists: true
      end
      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }
      desc_count = ActiveRecord::Base.lease_connection.select_value(<<~SQL.squish)
        SELECT COUNT(*) FROM all_ind_columns
         WHERE index_owner = SYS_CONTEXT('userenv', 'current_schema')
           AND index_name = 'IX_RT_SORT'
           AND descend = 'DESC'
      SQL
      expect(desc_count).to eq(1)
    end

    it "dumps a single-column DESC index" do
      schema_define do
        add_index :test_idx_sort_dump, :last_name,
                  name: "ix_single_desc", order: :desc
      end
      output = dump_table_schema "test_idx_sort_dump"
      expect(output).to match(/t\.index \[.*last_name.*\], name: "ix_single_desc", order: \{ last_name: :desc \}/im)
    end

    it "dumps a function-based DESC index without invalid order hash" do
      # Function-based + DESC: AR core's hash formatter cannot emit
      # `order: { LOWER("NAME"): :desc }` as valid Ruby (the key is not a
      # bare identifier). The reader skips DESC tracking in that case so
      # the dump stays parseable; DESC fidelity is lost on round-trip.
      schema_define do
        add_index :test_idx_sort_dump, "LOWER(last_name)",
                  name: "ix_expr_desc", order: :desc
      end
      output = dump_table_schema "test_idx_sort_dump"
      expect(output).to include('name: "ix_expr_desc"')
      expect(output).not_to match(/order: \{ LOWER/)
    end
  end

  describe "INVISIBLE index" do
    before(:each) do
      skip "Not supported in this database version" unless ActiveRecord::Base.lease_connection.supports_disabling_indexes?
      schema_define do
        create_table :test_idx_visibility_dump, force: true do |t|
          t.string :name
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_idx_visibility_dump, if_exists: true
      end
    end

    it "dumps `enabled: false` for an INVISIBLE index" do
      schema_define do
        add_index :test_idx_visibility_dump, :name,
                  name: "ix_dump_invisible", enabled: false
      end
      output = dump_table_schema "test_idx_visibility_dump"
      expect(output).to match(/t\.index \[.*name.*\], name: "ix_dump_invisible", enabled: false/im)
    end

    it "round-trips an INVISIBLE index through dump and load" do
      schema_define do
        add_index :test_idx_visibility_dump, :name,
                  name: "ix_rt_invisible", enabled: false
      end
      dumped = dump_table_schema "test_idx_visibility_dump"
      schema_define do
        drop_table :test_idx_visibility_dump, if_exists: true
      end
      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }
      visibility = ActiveRecord::Base.lease_connection.select_value(<<~SQL.squish)
        SELECT visibility FROM all_indexes
         WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
           AND index_name = 'IX_RT_INVISIBLE'
      SQL
      expect(visibility).to eq("INVISIBLE")
    end

    it "does not emit `enabled:` for VISIBLE indexes" do
      schema_define do
        add_index :test_idx_visibility_dump, :name, name: "ix_dump_visible"
      end
      output = dump_table_schema "test_idx_visibility_dump"
      expect(output).to include('name: "ix_dump_visible"')
      expect(output).not_to match(/enabled:/)
    end
  end

  describe "foreign key constraints" do
    # Recreate the canonical tables before each example. One example
    # (`should include primary_key when reference column name is not 'id'`)
    # mutates the schema by replacing test_posts/test_comments with
    # tables that lack `test_post_id`; under :random order any FK
    # example that runs after it then fails with
    # `ORA-00904: "TEST_POST_ID": invalid identifier`. Resetting the
    # tables per-example keeps every example independent of order.
    before(:each) do
      schema_define do
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
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
        remove_foreign_key :test_comments, :test_posts, if_exists: true
        remove_foreign_key :test_comments, name: "comments_posts_baz_fooz_fk", if_exists: true
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

    it "should include deferrable initially deferred foreign key in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, deferrable: :deferred
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts", deferrable: :deferred/)
    end

    it "should include deferrable initially immediate foreign key in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, deferrable: :immediate
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts", deferrable: :immediate/)
    end

    it "should not emit deferrable option when foreign key is not deferrable" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts"$/)
    end

    it "should not include foreign keys on ignored table names in schema dump" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect(standard_dump(ignore_tables: %w(test_comments))).not_to match(/add_foreign_key "test_comments"/)
    end

    it "dumps validate: false for NOVALIDATE foreign keys" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, validate: false
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts".*validate: false/)
    end

    it "round-trips validate: false on a foreign key through dump and load" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, validate: false
      end

      dumped = dump_table_schema "test_comments"
      schema_define do
        remove_foreign_key :test_comments, :test_posts, if_exists: true
      end

      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk).not_to be_nil
      expect(fk.options[:validate]).to be(false)
    end

    it "dumps enforced: false for DISABLEd foreign keys" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false
      end
      output = dump_table_schema "test_comments"
      expect(output).to match(/add_foreign_key "test_comments", "test_posts".*enforced: false/)
    end

    it "round-trips enforced: false alone (DISABLE VALIDATE) through dump and load" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false
      end

      dumped = dump_table_schema "test_comments"
      expect(dumped).to match(/add_foreign_key "test_comments", "test_posts".*enforced: false/)
      expect(dumped).not_to match(/validate: /)

      schema_define do
        remove_foreign_key :test_comments, :test_posts, if_exists: true
      end

      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk).not_to be_nil
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options.key?(:validate)).to be(false)
    end

    it "round-trips enforced: false, validate: false (DISABLE NOVALIDATE) through dump and load" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false, validate: false
      end

      dumped = dump_table_schema "test_comments"
      expect(dumped).to match(/add_foreign_key "test_comments", "test_posts".*validate: false.*enforced: false/)

      schema_define do
        remove_foreign_key :test_comments, :test_posts, if_exists: true
      end

      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk).not_to be_nil
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
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

  describe "with use_foreign_keys? returning false (foreign_keys: false in database.yml)" do
    before(:each) do
      schema_define do
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
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
        remove_foreign_key :test_comments, :test_posts, if_exists: true
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
      end
    end

    it "schema dump omits add_foreign_key statements" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      allow(@conn).to receive(:use_foreign_keys?).and_return(false)
      expect(standard_dump).not_to match(/add_foreign_key/)
    end

    it "add_foreign_key is a silent no-op" do
      allow(@conn).to receive(:use_foreign_keys?).and_return(false)
      expect {
        schema_define do
          add_foreign_key :test_comments, :test_posts
        end
      }.not_to raise_error
      expect(@conn.foreign_keys("test_comments")).to be_empty
    end

    it "add_foreign_key skips deferrable validation" do
      allow(@conn).to receive(:use_foreign_keys?).and_return(false)
      expect {
        schema_define do
          add_foreign_key :test_comments, :test_posts, deferrable: :always
        end
      }.not_to raise_error
      expect(@conn.foreign_keys("test_comments")).to be_empty
    end

    it "create_table with inline t.references foreign_key: true does not create the FK" do
      allow(@conn).to receive(:use_foreign_keys?).and_return(false)
      schema_define do
        drop_table :test_comments, if_exists: true
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post, foreign_key: true
        end
      end
      expect(@conn.foreign_keys("test_comments")).to be_empty
    end

    it "create_table inline t.references with an Oracle-invalid deferrable does not raise" do
      allow(@conn).to receive(:use_foreign_keys?).and_return(false)
      expect {
        schema_define do
          drop_table :test_comments, if_exists: true
          create_table :test_comments, force: true do |t|
            t.string :body, limit: 4000
            t.references :test_post, foreign_key: { deferrable: :always }
          end
        end
      }.not_to raise_error
      expect(@conn.foreign_keys("test_comments")).to be_empty
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

  describe "check constraints" do
    before(:each) do
      schema_define do
        create_table :test_products, force: true do |t|
          t.integer :price
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_products, if_exists: true
      end
    end

    it "dumps a check constraint as t.check_constraint inside create_table" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "price_dump_check"
      end
      output = dump_table_schema "test_products"
      expect(output).to match(/t\.check_constraint .*name: "price_dump_check"/)
    end

    it "round-trips a check constraint through dump and load" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "price_rt_check"
      end

      dumped = dump_table_schema "test_products"
      schema_define do
        drop_table :test_products, if_exists: true
      end

      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "price_rt_check" }
      expect(cc).not_to be_nil
    end

    it "dumps validate: false for NOVALIDATE check constraints" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "novalidate_dump", validate: false
      end
      output = dump_table_schema "test_products"
      expect(output).to match(/add_check_constraint "test_products".*name: "novalidate_dump".*validate: false/)
    end

    it "round-trips validate: false through dump and load" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "novalidate_rt", validate: false
      end

      dumped = dump_table_schema "test_products"
      schema_define do
        drop_table :test_products, if_exists: true
      end

      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "novalidate_rt" }
      expect(cc).not_to be_nil
      expect(cc.validate?).to be(false)
    end
  end

  describe "unique constraints" do
    before(:each) do
      schema_define do
        create_table :test_sections, force: true do |t|
          t.string :title
          t.integer :position
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_sections, if_exists: true
      end
    end

    it "dumps a stand-alone unique constraint as t.unique_constraint" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_position_dump"
      end
      output = dump_table_schema "test_sections"
      expect(output).to match(/t\.unique_constraint \["position"\], name: "uniq_position_dump"/)
    end

    it "dumps a divergent constraint via post-create_table add_unique_constraint and keeps the t.index line" do
      schema_define do
        add_index :test_sections, :position, name: :idx_div_dump
      end
      schema_define do
        add_unique_constraint :test_sections, name: "uniq_div_dump", using_index: :idx_div_dump
      end
      output = dump_table_schema "test_sections"
      expect(output).to match(/t\.index \["position"\], name: "idx_div_dump"/)
      expect(output).to match(/add_unique_constraint "test_sections", \["position"\], using_index: "idx_div_dump", name: "uniq_div_dump"/)
      expect(output).not_to match(/t\.unique_constraint .*using_index/)
    end

    it "round-trips a divergent unique constraint through dump and load" do
      schema_define do
        add_index :test_sections, :position, name: :idx_div_rt
      end
      schema_define do
        add_unique_constraint :test_sections, name: "uniq_div_rt", using_index: :idx_div_rt, deferrable: :deferred
      end

      dumped = dump_table_schema "test_sections"
      schema_define do
        drop_table :test_sections, if_exists: true
      end

      # Extract the body inside ActiveRecord::Schema[...].define(version: ...) do ... end
      # so loading does not insert the dumped version into schema_migrations.
      body = dumped[/ActiveRecord::Schema\[.+?\]\.define\(version: \d+\) do\n(.+)\nend\s*\z/m, 1]
      schema_define { instance_eval(body) }

      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_div_rt" }
      expect(uc).not_to be_nil
      expect(uc.using_index).to eq("idx_div_rt")
      expect(uc.deferrable).to eq(:deferred)
      expect(@conn.indexes(:test_sections).map(&:name)).to include("idx_div_rt")
    end

    it "does not double-emit t.index unique: true for an index that backs a unique constraint" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: :uniq_via_idx
      end
      output = dump_table_schema "test_sections"
      expect(output).not_to match(/t\.index .*"uniq_via_idx".*unique: true/)
      expect(output).to match(/t\.unique_constraint .*name: "uniq_via_idx"/)
    end

    it "should include deferrable initially deferred unique constraint in schema dump" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_def_dump", deferrable: :deferred
      end
      output = dump_table_schema "test_sections"
      expect(output).to match(/t\.unique_constraint .*deferrable: :deferred.*name: "uniq_def_dump"/)
    end

    it "should include deferrable initially immediate unique constraint in schema dump" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_imm_dump", deferrable: :immediate
      end
      output = dump_table_schema "test_sections"
      expect(output).to match(/t\.unique_constraint .*deferrable: :immediate.*name: "uniq_imm_dump"/)
    end

    it "should not emit deferrable option when unique constraint is not deferrable" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_plain_dump"
      end
      output = dump_table_schema "test_sections"
      expect(output).to match(/t\.unique_constraint \["position"\], name: "uniq_plain_dump"$/)
    end
  end

  describe "materialized views" do
    after(:each) do
      @conn.drop_if_exists("MATERIALIZED VIEW", "test_posts_mv")
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
      skip "Not supported in this database version" unless @conn.database_version >= "11"
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
      if @conn.database_version >= "11"
        class ::TestName < ActiveRecord::Base
          self.table_name = "test_names"
        end
      end
    end

    after(:all) do
      if @conn.database_version >= "11"
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
        if @conn.database_version >= "11"
          schema_define do
            add_index "test_names", "field_with_leading_space", name: "index_on_virtual_col"
          end
        end
      end

      after(:all) do
        if @conn.database_version >= "11"
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
