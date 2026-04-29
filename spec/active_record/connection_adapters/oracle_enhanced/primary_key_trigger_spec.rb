# frozen_string_literal: true

describe "primary_key_trigger" do
  include SchemaSpecHelper
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    @oracle12c_or_higher = @conn.database_version.first >= 12
  end

  after(:each) do
    ActiveRecord::Migration.suppress_messages do
      schema_define do
        drop_table :test_pk_triggers, if_exists: true
      end
    end
    @conn.schema_cache.clear!
  end

  def sequence_exists?(name)
    @conn.select_value(<<~SQL.squish, "SCHEMA").present?
      SELECT 1 FROM user_sequences WHERE sequence_name = '#{name.to_s.upcase}'
    SQL
  end

  def trigger_exists?(name)
    @conn.select_value(<<~SQL.squish, "SCHEMA").present?
      SELECT 1 FROM user_triggers WHERE trigger_name = '#{name.to_s.upcase}'
    SQL
  end

  describe "without primary_key_trigger: option" do
    it "creates a sequence-backed primary key without a trigger" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end

      expect(sequence_exists?(:test_pk_triggers_seq)).to be true
      expect(trigger_exists?(:test_pk_triggers_pkt)).to be false
      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be true
    end

    it "treats primary_key_trigger: false the same as the default" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: false do |t|
          t.string :name
        end
      end

      expect(trigger_exists?(:test_pk_triggers_pkt)).to be false
    end
  end

  describe "with primary_key_trigger: true" do
    it "creates a sequence + BEFORE INSERT trigger" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      expect(sequence_exists?(:test_pk_triggers_seq)).to be true
      expect(trigger_exists?(:test_pk_triggers_pkt)).to be true
    end

    it "skips prefetch_primary_key? for trigger-backed tables" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be false
    end

    it "allows inserting rows without supplying id (trigger fills via NEXTVAL)" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) { self.table_name = "test_pk_triggers" }

      row = klass.create!(name: "alpha")
      expect(row.id).to be_a(Integer)
      expect(row.id).to be > 0
    end

    it "allows inserting rows with an explicit id (trigger only fires when NULL)" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) { self.table_name = "test_pk_triggers" }

      row = klass.create!(id: 42, name: "bravo")
      expect(row.id).to eq(42)
    end

    it "honors the :trigger_name option" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true, trigger_name: :custom_pkt do |t|
          t.string :name
        end
      end

      expect(trigger_exists?(:custom_pkt)).to be true
      expect(trigger_exists?(:test_pk_triggers_pkt)).to be false
    end
  end

  describe "add_column with primary_key_trigger: true" do
    it "creates the trigger when adding a :primary_key column" do
      schema_define do
        create_table :test_pk_triggers, id: false do |t|
          t.string :name
        end
      end

      expect(trigger_exists?(:test_pk_triggers_pkt)).to be false

      @conn.add_column :test_pk_triggers, :id, :primary_key, primary_key_trigger: true

      expect(sequence_exists?(:test_pk_triggers_seq)).to be true
      expect(trigger_exists?(:test_pk_triggers_pkt)).to be true
    end

    it "raises when adding a non-:primary_key column with primary_key_trigger: true" do
      schema_define do
        create_table :test_pk_triggers, id: false do |t|
          t.string :name
        end
      end

      expect {
        @conn.add_column :test_pk_triggers, :id, :integer, primary_key_trigger: true
      }.to raise_error(ArgumentError, /requires the column type to be `:primary_key`/)
    end
  end

  describe "prefetch_primary_key? cache invalidation" do
    it "is invalidated when a trigger-backed table is dropped and recreated as plain sequence-backed" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be false

      schema_define do
        drop_table :test_pk_triggers
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end
      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be true
    end

    it "is invalidated when a sequence-backed table is dropped and recreated as trigger-backed" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end
      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be true

      schema_define do
        drop_table :test_pk_triggers
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be false
    end
  end

  describe "invalid primary_key_trigger: true combinations" do
    it "raises when combined with id: false" do
      expect {
        @conn.create_table :test_pk_triggers, primary_key_trigger: true, id: false, force: true do |t|
          t.string :name
        end
      }.to raise_error(ArgumentError, /requires `id: :primary_key`/)
    end

    it "raises when combined with id: :integer" do
      expect {
        @conn.create_table :test_pk_triggers, primary_key_trigger: true, id: :integer, force: true do |t|
          t.string :name
        end
      }.to raise_error(ArgumentError, /requires `id: :primary_key`/)
    end

    it "raises when combined with id: :uuid" do
      expect {
        @conn.create_table :test_pk_triggers, primary_key_trigger: true, id: :uuid, force: true do |t|
          t.string :name
        end
      }.to raise_error(ArgumentError, /requires `id: :primary_key`/)
    end

    it "raises when combined with a composite primary key" do
      expect {
        @conn.create_table :test_pk_triggers, primary_key_trigger: true, primary_key: [:a, :b], force: true do |t|
          t.string :a
          t.string :b
        end
      }.to raise_error(ArgumentError, /composite primary key/)
    end

    it "raises when combined with identity: true" do
      skip "requires Oracle 12.1+" unless @oracle12c_or_higher

      expect {
        @conn.create_table :test_pk_triggers, primary_key_trigger: true, identity: true, force: true do |t|
          t.string :name
        end
      }.to raise_error(ArgumentError, /cannot be combined with `identity: true`/)
    end
  end

  describe "schema_dumper roundtrip" do
    it "emits primary_key_trigger: true for trigger-backed tables" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include('create_table "test_pk_triggers"')
      expect(stream.string).to include("primary_key_trigger: true")
    end

    it "does not emit primary_key_trigger: true for plain sequence-backed tables" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include('create_table "test_pk_triggers"')
      expect(stream.string).not_to include("primary_key_trigger")
    end

    it "does not emit primary_key_trigger: true for identity tables" do
      skip "requires Oracle 12.1+" unless @oracle12c_or_higher

      schema_define do
        create_table :test_pk_triggers, identity: true do |t|
          t.string :name
        end
      end

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include('create_table "test_pk_triggers"')
      expect(stream.string).to include("identity: true")
      expect(stream.string).not_to include("primary_key_trigger")
    end

    it "emits :trigger_name when non-default" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true, trigger_name: :custom_pkt do |t|
          t.string :name
        end
      end

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include("primary_key_trigger: true")
      expect(stream.string).to include('trigger_name: "custom_pkt"')
    end

    it "does not emit :trigger_name when matching the default" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include("primary_key_trigger: true")
      expect(stream.string).not_to include("trigger_name:")
    end
  end

  describe "low-level INSERT with primary_key_trigger: true" do
    before(:each) do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
    end

    it "populates primary key when raw INSERT does not supply id" do
      expect {
        @conn.execute "INSERT INTO test_pk_triggers (name) VALUES ('alpha')"
      }.not_to raise_error
    end

    it "returns the generated id from connection.insert" do
      insert_id = Array(@conn.insert("INSERT INTO test_pk_triggers (name) VALUES ('alpha')", nil, "id")).first
      expect(@conn.select_value("SELECT test_pk_triggers_seq.currval FROM dual")).to eq(insert_id)
    end

    it "does not raise NoMethodError for :returning_id Symbol when logging" do
      skip "see #2619: ruby-oci8 + cursor_sharing=force x RETURNING INTO :returning_id half-duplex deadlock"
      set_logger
      @conn.reconnect! unless @conn.active?
      @conn.insert("INSERT INTO test_pk_triggers (name) VALUES ('alpha')", nil, "id")
      expect(@logger.output(:error)).not_to match(/Could not log .*NoMethodError.*returning_id/)
      clear_logger
    end
  end

  describe "with non-default :primary_key" do
    it "uses the named primary key column with the trigger" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true, primary_key: "employee_id" do |t|
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_pk_triggers"
        self.primary_key = "employee_id"
      end

      row = klass.create!(name: "alpha")
      expect(row.employee_id).to be_a(Integer)
      expect(row.employee_id).to be > 0
    end
  end

  describe "with non-default :sequence_name" do
    it "creates the trigger using the named sequence" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true, sequence_name: :test_pk_triggers_s do |t|
          t.string :name
        end
      end

      expect(sequence_exists?(:test_pk_triggers_s)).to be true
      expect(sequence_exists?(:test_pk_triggers_seq)).to be false
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_pk_triggers"
        self.sequence_name = :test_pk_triggers_s
      end
      row = klass.create!(name: "alpha")
      expect(row.id).to be_a(Integer)
    end
  end

  describe "long identifiers" do
    before do
      skip "requires extended identifier length (Oracle 12.2+)" if @conn.max_identifier_length < 128
    end

    after(:each) do
      tables_to_drop = [@long_table_name, @long_unicode_table_name].compact
      schema_define do
        tables_to_drop.each do |t|
          drop_table t.to_sym, if_exists: true
        end
      end
      @conn.schema_cache.clear!
    end

    it "computes default_trigger_name with byte-bounded truncation" do
      max = @conn.max_identifier_length
      @long_table_name = "a" * (max - 4)
      derived = @conn.default_trigger_name(@long_table_name)
      expect(derived.bytesize).to be <= max
      expect(derived).to end_with("_pkt")
    end

    it "creates the trigger with a truncated default name when the table name fills the budget" do
      max = @conn.max_identifier_length
      @long_table_name = "a" * max
      table_name_local = @long_table_name
      schema_define do
        create_table table_name_local.to_sym, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      derived = @conn.default_trigger_name(@long_table_name)
      expect(derived.bytesize).to be <= max
      expect(trigger_exists?(derived)).to be true
    end

    it "byteslices the trigger name at a UTF-8 codepoint boundary for multibyte table names" do
      max = @conn.max_identifier_length
      # "é" is 2 bytes in UTF-8. Build a name whose pre-truncation byte length
      # exceeds the budget so the slice has to land in the middle of a
      # multibyte character on its first attempt.
      @long_unicode_table_name = "é" * ((max / 2) + 5)
      derived = @conn.default_trigger_name(@long_unicode_table_name)
      expect(derived.bytesize).to be <= max
      expect(derived).to be_valid_encoding
      expect(derived).to end_with("_pkt")
    end
  end

  describe "manual trigger creation via raw DDL" do
    it "accepts the PL/SQL block syntax for CREATE OR REPLACE TRIGGER" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end

      expect do
        @conn.execute <<~SQL
          CREATE OR REPLACE TRIGGER test_pk_triggers_pkt
            BEFORE INSERT ON test_pk_triggers FOR EACH ROW
          BEGIN
            IF inserting THEN
              IF :new.id IS NULL THEN
                SELECT test_pk_triggers_seq.NEXTVAL INTO :new.id FROM dual;
              END IF;
            END IF;
          END;
        SQL
      end.not_to raise_error
    end
  end

  describe "auto_populated? on the primary key column" do
    it "reports true for a trigger-backed primary key" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end

      pk_column = @conn.columns(:test_pk_triggers).find { |c| c.name == "id" }
      expect(pk_column.auto_populated?).to be true
    end

    it "reports false for a plain sequence-backed primary key" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
        end
      end

      pk_column = @conn.columns(:test_pk_triggers).find { |c| c.name == "id" }
      expect(pk_column.auto_populated?).to be false
    end

    it "reports false when only an unrelated BEFORE INSERT trigger exists" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
          t.string :note
        end
      end

      @conn.execute <<~SQL
        CREATE OR REPLACE TRIGGER test_pk_triggers_audit
          BEFORE INSERT ON test_pk_triggers FOR EACH ROW
        BEGIN
          :new.note := 'audited';
        END;
      SQL

      pk_column = @conn.columns(:test_pk_triggers).find { |c| c.name == "id" }
      expect(pk_column.auto_populated?).to be false
    end

    it "drives _returning_columns_for_insert for trigger-backed tables" do
      schema_define do
        create_table :test_pk_triggers, primary_key_trigger: true do |t|
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) { self.table_name = "test_pk_triggers" }

      expect(klass._returning_columns_for_insert(@conn)).to eq(["id"])
    end
  end

  describe "trigger_backed_primary_key? false-positive guard" do
    it "ignores BEFORE INSERT row triggers that do not fill the PK from a sequence" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
          t.string :note
        end
      end

      @conn.execute <<~SQL
        CREATE OR REPLACE TRIGGER test_pk_triggers_audit
          BEFORE INSERT ON test_pk_triggers FOR EACH ROW
        BEGIN
          :new.note := 'audited';
        END;
      SQL

      expect(@conn.prefetch_primary_key?(:test_pk_triggers)).to be true
    end

    it "does not emit primary_key_trigger: in the schema dump for those tables" do
      schema_define do
        create_table :test_pk_triggers do |t|
          t.string :name
          t.string :note
        end
      end

      @conn.execute <<~SQL
        CREATE OR REPLACE TRIGGER test_pk_triggers_audit
          BEFORE INSERT ON test_pk_triggers FOR EACH ROW
        BEGIN
          :new.note := 'audited';
        END;
      SQL

      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = @conn.data_sources - ["test_pk_triggers"]
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
      ActiveRecord::SchemaDumper.ignore_tables = []

      expect(stream.string).to include('create_table "test_pk_triggers"')
      expect(stream.string).not_to include("primary_key_trigger")
    end
  end
end
