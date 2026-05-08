# frozen_string_literal: true

# Tests for the DBMS_METADATA-backed structure_dump path.
#
# Unlike `structure_dump_spec.rb`, which assumes the legacy ALL_*-based
# implementation and asserts on exact DDL text, this file exercises the
# default backend (DBMS_METADATA) and asserts only on the *shape* the dump
# is required to produce: each call returns a non-empty SQL stream, the
# stream contains the expected statement keyword for each kind of object,
# and the stream is reloadable on a fresh schema via
# `execute_structure_dump`.
#
# This mirrors how `pg_dump` and `mysqldump` are tested upstream: the
# implementation's exact byte output is not part of the contract;
# round-trip-loadability is.
RSpec.describe "OracleEnhancedAdapter DBMS_METADATA structure dump" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  before(:each) do
    schema_define do
      drop_table :test_dbms_metadata_comments, if_exists: true
      drop_table :test_dbms_metadata_children, if_exists: true
      drop_table :test_dbms_metadata_posts, if_exists: true
    end
  end

  after(:each) do
    schema_define do
      drop_table :test_dbms_metadata_comments, if_exists: true
      drop_table :test_dbms_metadata_children, if_exists: true
      drop_table :test_dbms_metadata_posts, if_exists: true
    end
  end

  describe "structure_dump_method selection" do
    it "defaults to :auto" do
      expect(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method).to eq(:auto)
    end

    it ":auto resolves to :dbms_metadata on Oracle 12.1+" do
      original = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method
      skip "requires Oracle 12.1+" unless @conn.use_dbms_metadata_dump?
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = :auto
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
      end
      dump = @conn.structure_dump
      # DBMS_METADATA always quotes identifiers; data_dictionary does not.
      expect(dump).to match(/CREATE TABLE\s+"TEST_DBMS_METADATA_POSTS"/i)
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = original
    end

    it "delegates to the data-dictionary backend when set to :data_dictionary" do
      original = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = :data_dictionary
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
      end
      dump = @conn.structure_dump
      expect(dump).to match(/test_dbms_metadata_posts/i)
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = original
    end

    it "raises ArgumentError for an unknown value" do
      original = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = :bogus
      expect { @conn.structure_dump }.to raise_error(ArgumentError, /Unknown structure_dump_method :bogus/)
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = original
    end

    it "raises ArgumentError when :dbms_metadata is forced on a pre-12.1 server" do
      original = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method
      skip "this case is only reachable on Oracle < 12.1" if @conn.use_dbms_metadata_dump?
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = :dbms_metadata
      expect { @conn.structure_dump }.to raise_error(
        ArgumentError, /:dbms_metadata requires Oracle 12\.1 or later/
      )
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.structure_dump_method = original
    end
  end

  describe "structure_dump (DBMS_METADATA path)" do
    before(:each) do
      skip "requires Oracle 12.1+ for the DBMS_METADATA path" unless @conn.use_dbms_metadata_dump?
    end

    it "emits CREATE TABLE for each table" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
          t.text :body
          t.timestamps
        end
      end
      dump = @conn.structure_dump
      expect(dump).to match(/CREATE TABLE\s+"?TEST_DBMS_METADATA_POSTS"?/i)
    end

    it "includes indexes as separate CREATE INDEX statements" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
        add_index :test_dbms_metadata_posts, :title, name: "ix_test_dbms_metadata_title"
      end
      dump = @conn.structure_dump
      expect(dump).to match(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+"?IX_TEST_DBMS_METADATA_TITLE"?/i)
    end

    it "emits referential constraints as ALTER TABLE … ADD CONSTRAINT after the tables" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
        create_table :test_dbms_metadata_children, force: true do |t|
          t.references :test_dbms_metadata_post, foreign_key: { to_table: :test_dbms_metadata_posts }
        end
      end
      dump = @conn.structure_dump
      expect(dump).to match(/ALTER\s+TABLE\s+"?TEST_DBMS_METADATA_CHILDREN"?\s+ADD\s+CONSTRAINT/i)
      expect(dump).to match(/REFERENCES\s+"?TEST_DBMS_METADATA_POSTS"?/i)
    end

    it "emits NOVALIDATE for check constraints added with validate: false" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.integer :price
        end
      end
      @conn.add_check_constraint(:test_dbms_metadata_posts, "price > 0", name: "dbms_meta_novalidate_chk", validate: false)
      dump = @conn.structure_dump
      expect(dump).to match(/CONSTRAINT\s+"DBMS_META_NOVALIDATE_CHK"\s+CHECK\s*\(.+\)\s+.*\bNOVALIDATE\b/im)
    end

    it "emits NOVALIDATE for foreign keys added with validate: false" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
        create_table :test_dbms_metadata_children, force: true do |t|
          t.references :test_dbms_metadata_post
        end
      end
      @conn.add_foreign_key :test_dbms_metadata_children, :test_dbms_metadata_posts,
                            column: :test_dbms_metadata_post_id,
                            name: "dbms_meta_novalidate_fk", validate: false
      dump = @conn.structure_dump
      expect(dump).to match(/CONSTRAINT\s+"DBMS_META_NOVALIDATE_FK"\s+FOREIGN\s+KEY.+REFERENCES\s+"TEST_DBMS_METADATA_POSTS".+\bNOVALIDATE\b/im)
    end

    it "emits COMMENT ON TABLE / COMMENT ON COLUMN for documented tables" do
      schema_define do
        create_table :test_dbms_metadata_comments, force: true, comment: "table-level comment" do |t|
          t.string :title, comment: "column-level comment"
        end
      end
      dump = @conn.structure_dump
      expect(dump).to match(/COMMENT\s+ON\s+TABLE\s+"?TEST_DBMS_METADATA_COMMENTS"?\s+IS\s+'table-level comment'/i)
      expect(dump).to match(/COMMENT\s+ON\s+COLUMN\s+"?TEST_DBMS_METADATA_COMMENTS"?\."?TITLE"?\s+IS\s+'column-level comment'/i)
    end

    it "suppresses storage and tablespace clauses (mysqldump / pg_dump --schema-only convention)" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :title
        end
      end
      dump = @conn.structure_dump
      expect(dump).not_to match(/STORAGE\s*\(/i)
      expect(dump).not_to match(/TABLESPACE\s+/i)
      expect(dump).not_to match(/PCTFREE\s+/i)
    end

    it "does not emit a standalone CREATE INDEX for a UNIQUE constraint's backing index" do
      schema_define do
        create_table :test_dbms_metadata_posts, force: true do |t|
          t.string :email
        end
        add_index :test_dbms_metadata_posts, :email, unique: true, name: "ix_test_dbms_metadata_email"
      end
      dump = @conn.structure_dump
      # `CONSTRAINTS=TRUE` already inlines the unique constraint (and its
      # backing index) into the CREATE TABLE DDL. Emitting a separate
      # `CREATE UNIQUE INDEX` for the same name would duplicate it.
      standalone_index_stmts = dump.split("\n\n/\n\n").select do |stmt|
        stmt.match?(/\ACREATE\s+UNIQUE\s+INDEX\s+"?IX_TEST_DBMS_METADATA_EMAIL"?/i)
      end
      expect(standalone_index_stmts).to be_empty
    end
  end

  describe "structure_dump_db_stored_code (DBMS_METADATA path)" do
    before(:each) do
      skip "requires Oracle 12.1+ for the DBMS_METADATA path" unless @conn.use_dbms_metadata_dump?
      @conn.drop_if_exists("PACKAGE", "test_dbms_metadata_pkg")
    end

    after(:each) do
      @conn.drop_if_exists("PACKAGE", "test_dbms_metadata_pkg")
    end

    it "emits a PACKAGE BODY only once" do
      @conn.execute <<~SQL
        CREATE OR REPLACE PACKAGE test_dbms_metadata_pkg AS
          FUNCTION add_one(p_id IN NUMBER) RETURN NUMBER;
        END test_dbms_metadata_pkg;
      SQL
      @conn.execute <<~SQL
        CREATE OR REPLACE PACKAGE BODY test_dbms_metadata_pkg AS
          FUNCTION add_one(p_id IN NUMBER) RETURN NUMBER IS
          BEGIN
            RETURN p_id + 1;
          END;
        END test_dbms_metadata_pkg;
      SQL
      dump = @conn.structure_dump_db_stored_code
      # `GET_DDL("PACKAGE", ...)` returns spec + body; selecting 'PACKAGE BODY'
      # in the source query as well would emit the body a second time.
      body_count = dump.scan(/PACKAGE\s+BODY\s+"?TEST_DBMS_METADATA_PKG"?/i).size
      expect(body_count).to eq(1)
    end

    # Note: a true round-trip (drop tables, replay full dump, verify) is
    # impractical here because `structure_dump` is whole-schema; replaying it
    # collides (ORA-00955) with sibling objects from other specs that share
    # the schema. The structural assertions above cover the dump's
    # output shape, which is the per-PR contract; full round-trip lives in
    # the database_tasks integration spec.
  end

  describe "schema: connection option" do
    before(:each) do
      schema_define do
        create_table :test_dbms_metadata_marker, force: true do |t|
          t.string :title
        end
      end
    end

    after(:each) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.lease_connection
      schema_define { drop_table :test_dbms_metadata_marker, if_exists: true }
    end

    it "queries against the schema configured via :schema, not the connecting user" do
      # Sanity: the default-user dump sees the marker.
      expect(@conn.structure_dump).to match(/CREATE TABLE\s+"TEST_DBMS_METADATA_MARKER"/i)

      ActiveRecord::Base.establish_connection(CONNECTION_WITH_SCHEMA_PARAMS)
      schema_conn = ActiveRecord::Base.lease_connection
      expect(schema_conn.current_schema).to eq(DATABASE_SCHEMA.upcase)
      # The marker belongs to DATABASE_USER; with :schema set the dump
      # walks the alternate schema and must not see it.
      expect(schema_conn.structure_dump).not_to match(/CREATE TABLE\s+"TEST_DBMS_METADATA_MARKER"/i)
    end
  end
end
