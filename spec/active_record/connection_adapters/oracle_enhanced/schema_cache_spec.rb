# frozen_string_literal: true

describe "OracleEnhancedAdapter schema cache" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @pool = ActiveRecord::Base.connection_pool
    schema_define do
      create_table :test_schema_cache_posts, force: true do |t|
        t.string :title
        t.text :body
        t.timestamps null: false
      end
      add_index :test_schema_cache_posts, :title
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_schema_cache_posts
    end
  end

  let(:schema_cache) { @pool.schema_cache }

  describe "columns" do
    it "returns columns for a table" do
      columns = schema_cache.columns(@pool, "test_schema_cache_posts")
      expect(columns).not_to be_empty
      column_names = columns.map(&:name)
      expect(column_names).to include("id", "title", "body", "created_at", "updated_at")
    end

    it "caches columns after first access" do
      schema_cache.columns(@pool, "test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be true
    end
  end

  describe "columns_hash" do
    it "returns a hash of columns indexed by name" do
      columns_hash = schema_cache.columns_hash(@pool, "test_schema_cache_posts")
      expect(columns_hash).to be_a(Hash)
      expect(columns_hash["title"]).not_to be_nil
      expect(columns_hash["title"].name).to eq("title")
    end
  end

  describe "primary_keys" do
    it "returns the primary key for a table" do
      pk = schema_cache.primary_keys(@pool, "test_schema_cache_posts")
      expect(pk).to eq("id")
    end
  end

  describe "indexes" do
    it "returns indexes for a table" do
      indexes = schema_cache.indexes(@pool, "test_schema_cache_posts")
      expect(indexes).not_to be_empty
      index_columns = indexes.map(&:columns).flatten
      expect(index_columns).to include("title")
    end
  end

  describe "data_source_exists?" do
    it "returns true for an existing table" do
      expect(schema_cache.data_source_exists?(@pool, "test_schema_cache_posts")).to be true
    end

    it "returns false for a non-existing table" do
      expect(schema_cache.data_source_exists?(@pool, "test_nonexistent_table")).to be false
    end
  end

  describe "dump and load" do
    it "can dump and load schema cache" do
      # Populate cache
      schema_cache.columns(@pool, "test_schema_cache_posts")
      schema_cache.primary_keys(@pool, "test_schema_cache_posts")
      schema_cache.indexes(@pool, "test_schema_cache_posts")

      tmpfile = Tempfile.new(["schema_cache", ".yml"])
      begin
        schema_cache.dump_to(tmpfile.path)
        expect(File.exist?(tmpfile.path)).to be true
        expect(File.size(tmpfile.path)).to be > 0
      ensure
        tmpfile.close
        tmpfile.unlink
      end
    end

    it "produces consistent dump output" do
      # Populate cache
      schema_cache.columns(@pool, "test_schema_cache_posts")
      schema_cache.primary_keys(@pool, "test_schema_cache_posts")
      schema_cache.indexes(@pool, "test_schema_cache_posts")

      tmpfile1 = Tempfile.new(["schema_cache1", ".yml"])
      tmpfile2 = Tempfile.new(["schema_cache2", ".yml"])
      begin
        schema_cache.dump_to(tmpfile1.path)
        schema_cache.dump_to(tmpfile2.path)

        dump1 = File.read(tmpfile1.path)
        dump2 = File.read(tmpfile2.path)
        expect(dump1).to eq(dump2)
      ensure
        tmpfile1.close
        tmpfile1.unlink
        tmpfile2.close
        tmpfile2.unlink
      end
    end
  end

  describe "clear_data_source_cache!" do
    it "clears cache for a specific table" do
      schema_cache.columns(@pool, "test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be true

      schema_cache.clear_data_source_cache!(@conn, "test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be false
    end
  end

  describe "version" do
    it "returns a schema version" do
      version = schema_cache.version(@pool)
      expect(version).not_to be_nil
    end
  end
end
