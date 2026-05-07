# frozen_string_literal: true

require "tempfile"

RSpec.describe "OracleEnhancedAdapter schema cache" do
  include SchemaSpecHelper

  PERMITTED_YAML_CLASSES = [
    ActiveRecord::ConnectionAdapters::OracleEnhanced::Column,
    ActiveRecord::ConnectionAdapters::OracleEnhanced::IndexDefinition,
    ActiveRecord::ConnectionAdapters::OracleEnhanced::TypeMetadata,
    ActiveRecord::ConnectionAdapters::SqlTypeMetadata,
    ActiveRecord::ConnectionAdapters::SchemaCache,
    ActiveRecord::Type::Integer,
    ActiveRecord::Type::String,
    ActiveRecord::Type::DateTime,
    ActiveRecord::Type::Boolean,
    ActiveRecord::Type::Decimal,
    ActiveRecord::Type::Text,
    ActiveRecord::Type::OracleEnhanced::Integer,
    ActiveRecord::Type::OracleEnhanced::String,
    ActiveRecord::Type::OracleEnhanced::Text,
    Symbol,
  ].freeze

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
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

  let(:schema_cache) { ActiveRecord::Base.connection_pool.schema_cache }

  describe "columns" do
    it "returns columns for a table" do
      columns = schema_cache.columns("test_schema_cache_posts")
      expect(columns).not_to be_empty
      column_names = columns.map(&:name)
      expect(column_names).to include("id", "title", "body", "created_at", "updated_at")
    end

    it "caches columns after first access" do
      schema_cache.columns("test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be true
    end
  end

  describe "columns_hash" do
    it "returns a hash of columns indexed by name" do
      columns_hash = schema_cache.columns_hash("test_schema_cache_posts")
      expect(columns_hash).to be_a(Hash)
      expect(columns_hash["title"]).not_to be_nil
      expect(columns_hash["title"].name).to eq("title")
    end
  end

  describe "primary_keys" do
    it "returns the primary key for a table" do
      pk = schema_cache.primary_keys("test_schema_cache_posts")
      expect(pk).to eq("id")
    end
  end

  describe "indexes" do
    it "returns indexes for a table" do
      indexes = schema_cache.indexes("test_schema_cache_posts")
      expect(indexes).not_to be_empty
      index_columns = indexes.map(&:columns).flatten
      expect(index_columns).to include("title")
    end
  end

  describe "data_source_exists?" do
    it "returns true for an existing table" do
      expect(schema_cache.data_source_exists?("test_schema_cache_posts")).to be true
    end

    it "returns false for a non-existing table" do
      expect(schema_cache.data_source_exists?("test_nonexistent_table")).to be false
    end
  end

  describe "dump and load" do
    it "can dump and load schema cache" do
      schema_cache.columns("test_schema_cache_posts")
      schema_cache.primary_keys("test_schema_cache_posts")
      schema_cache.indexes("test_schema_cache_posts")

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
      schema_cache.columns("test_schema_cache_posts")
      schema_cache.primary_keys("test_schema_cache_posts")
      schema_cache.indexes("test_schema_cache_posts")

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
      schema_cache.columns("test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be true

      schema_cache.clear_data_source_cache!("test_schema_cache_posts")
      expect(schema_cache.cached?("test_schema_cache_posts")).to be false
    end
  end

  describe "version" do
    it "returns a schema version" do
      version = schema_cache.version
      expect(version).not_to be_nil
    end
  end

  describe "prefetch_primary_key? after schema cache reload" do
    let(:conn) { ActiveRecord::Base.connection }

    it "carries identity / trigger_assigned flags through the YAML round trip" do
      original = schema_cache.columns("test_schema_cache_posts").find { |c| c.name == "id" }
      expect(original).not_to be_nil

      yaml = YAML.dump(original)
      restored = YAML.safe_load(yaml, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)

      expect(restored).to be_a(ActiveRecord::ConnectionAdapters::OracleEnhanced::Column)
      expect(restored.instance_variable_get(:@identity)).to eq(original.instance_variable_get(:@identity))
      expect(restored.instance_variable_get(:@trigger_assigned)).to eq(original.instance_variable_get(:@trigger_assigned))
      expect(restored.auto_incremented_by_db?).to eq(original.auto_incremented_by_db?)
      expect(restored.auto_populated?).to eq(original.auto_populated?)
    end

    it "leaves @identity and @trigger_assigned undefined when YAML predates these keys" do
      original = schema_cache.columns("test_schema_cache_posts").find { |c| c.name == "id" }
      yaml = YAML.dump(original)

      old_yaml = yaml.lines.reject { |l| l.start_with?("identity:", "trigger_assigned:") }.join
      restored = YAML.safe_load(old_yaml, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)

      expect(restored).to be_a(ActiveRecord::ConnectionAdapters::OracleEnhanced::Column)
      expect(restored.instance_variable_defined?(:@identity)).to be false
      expect(restored.instance_variable_defined?(:@trigger_assigned)).to be false
    end

    it "returns true for a sequence-backed primary key without firing catalog SQL" do
      warm_up_schema_cache_for("test_schema_cache_posts")
      conn.send(:instance_variable_set, :@prefetch_primary_key_cache, {})

      result, catalog = capture_pk_lookup { conn.prefetch_primary_key?("test_schema_cache_posts") }
      expect(result).to be true
      expect(catalog).to be_empty
    end

    context "with a trigger-backed primary key" do
      before(:all) do
        schema_define do
          create_table :test_schema_cache_legacy_posts, force: true, primary_key_trigger: true do |t|
            t.string :title
          end
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_schema_cache_legacy_posts rescue nil
        end
      end

      it "returns false without firing catalog SQL once the column is cached" do
        warm_up_schema_cache_for("test_schema_cache_legacy_posts")
        conn.send(:instance_variable_set, :@prefetch_primary_key_cache, {})

        result, catalog = capture_pk_lookup { conn.prefetch_primary_key?("test_schema_cache_legacy_posts") }
        expect(result).to be false
        expect(catalog).to be_empty
      end

      it "carries trigger_assigned = true through the YAML round trip" do
        original = schema_cache.columns("test_schema_cache_legacy_posts").find { |c| c.name == "id" }
        expect(original.auto_populated?).to be true

        restored = YAML.safe_load(YAML.dump(original), permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)
        expect(restored.auto_populated?).to be true
        expect(restored.instance_variable_get(:@trigger_assigned)).to be true
      end
    end

    context "with an identity primary key" do
      before(:all) do
        skip "identity columns require Oracle 12c+" unless ActiveRecord::Base.connection.supports_identity_columns?
        schema_define do
          create_table :test_schema_cache_identity_posts, force: true, identity: true do |t|
            t.string :title
          end
        end
      end

      after(:all) do
        next unless ActiveRecord::Base.connection.supports_identity_columns?
        schema_define do
          drop_table :test_schema_cache_identity_posts rescue nil
        end
      end

      it "returns false without firing catalog SQL once the column is cached" do
        warm_up_schema_cache_for("test_schema_cache_identity_posts")
        conn.send(:instance_variable_set, :@prefetch_primary_key_cache, {})

        result, catalog = capture_pk_lookup { conn.prefetch_primary_key?("test_schema_cache_identity_posts") }
        expect(result).to be false
        expect(catalog).to be_empty
      end

      it "carries identity = true through the YAML round trip" do
        original = schema_cache.columns("test_schema_cache_identity_posts").find { |c| c.name == "id" }
        expect(original.auto_incremented_by_db?).to be true

        restored = YAML.safe_load(YAML.dump(original), permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)
        expect(restored.auto_incremented_by_db?).to be true
        expect(restored.instance_variable_get(:@identity)).to be true
      end
    end

    context "with a composite primary key" do
      before(:all) do
        schema_define do
          create_table :test_schema_cache_composite, primary_key: ["org_id", "user_id"], force: true do |t|
            t.integer :org_id, precision: 38, null: false
            t.integer :user_id, precision: 38, null: false
            t.string :name
          end
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_schema_cache_composite rescue nil
        end
      end

      it "returns false without firing catalog SQL once the cache is warmed" do
        warm_up_schema_cache_for("test_schema_cache_composite")
        conn.send(:instance_variable_set, :@prefetch_primary_key_cache, {})

        result, catalog = capture_pk_lookup { conn.prefetch_primary_key?("test_schema_cache_composite") }
        expect(result).to be false
        expect(catalog).to be_empty
      end
    end

    context "with no primary key" do
      before(:all) do
        schema_define do
          create_table :test_schema_cache_no_pk, force: true, id: false do |t|
            t.string :name
          end
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_schema_cache_no_pk rescue nil
        end
      end

      it "returns false without firing catalog SQL once the cache is warmed" do
        warm_up_schema_cache_for("test_schema_cache_no_pk")
        conn.send(:instance_variable_set, :@prefetch_primary_key_cache, {})

        result, catalog = capture_pk_lookup { conn.prefetch_primary_key?("test_schema_cache_no_pk") }
        expect(result).to be false
        expect(catalog).to be_empty
      end
    end

    it "preserves Oracle column metadata across full SchemaCache YAML round trip" do
      warm_up_schema_cache_for("test_schema_cache_posts")

      tmpfile = Tempfile.new(["schema_cache", ".yml"])
      begin
        schema_cache.dump_to(tmpfile.path)
        reloaded = YAML.safe_load_file(tmpfile.path, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)

        cols = reloaded.instance_variable_get(:@columns)["test_schema_cache_posts"]
        expect(cols).not_to be_nil
        id_col = cols.find { |c| c.name == "id" }
        expect(id_col).to be_a(ActiveRecord::ConnectionAdapters::OracleEnhanced::Column)
        expect(id_col.instance_variable_get(:@identity)).to be(false)
        expect(id_col.instance_variable_get(:@trigger_assigned)).to be(false)
      ensure
        tmpfile.close
        tmpfile.unlink
      end
    end

    def warm_up_schema_cache_for(table_name)
      cache = ActiveRecord::Base.connection_pool.schema_cache
      cache.data_source_exists?(table_name)
      cache.columns(table_name)
      cache.columns_hash(table_name)
      cache.primary_keys(table_name)
    end

    def capture_pk_lookup
      events = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        events << payload[:sql]
      end
      result = yield
      catalog = events.grep(/all_constraints|all_sequences|all_tab_identity_cols|all_triggers/i)
      [result, catalog]
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end

  describe "primary_key(table_name) for composite-PK tables" do
    let(:conn) { ActiveRecord::Base.connection }

    before(:all) do
      schema_define do
        create_table :test_schema_cache_composite_pk, primary_key: ["org_id", "user_id"], force: true do |t|
          t.integer :org_id, precision: 38, null: false
          t.integer :user_id, precision: 38, null: false
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_schema_cache_composite_pk rescue nil
      end
    end

    it "returns the composite primary key as an Array (Rails default behavior)" do
      expect(conn.primary_key("test_schema_cache_composite_pk")).to eq(["org_id", "user_id"])
    end
  end
end
