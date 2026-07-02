# frozen_string_literal: true

RSpec.describe "OracleEnhanced::CompatibilityBehavior resolution" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  def oracle_behavior
    ActiveRecord::ConnectionAdapters::OracleEnhanced::CompatibilityBehavior
  end

  it "resolves Migration[8.2] to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.2])).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "resolves Migration[8.1] to V8_1" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.1])).to eq oracle_behavior::V8_1
  end

  it "resolves Migration[7.0] to V8_1, which covers its own version and older" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[7.0])).to eq oracle_behavior::V8_1
  end

  it "resolves an unversioned migration to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration)).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "resolves ActiveRecord::Schema[8.1] to V8_1, like Migration[8.1]" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema[8.1])).to eq oracle_behavior::V8_1
  end

  it "resolves ActiveRecord::Schema[8.2] and plain ActiveRecord::Schema to the no-op base behavior" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema[8.2])).to eq ActiveRecord::Migration::CompatibilityBehavior
    expect(@conn.compatibility_behavior_for(ActiveRecord::Schema)).to eq ActiveRecord::Migration::CompatibilityBehavior
  end

  it "gives a running Migration[8.1] a V8_1 behavior instance through the Rails hook" do
    migration = Class.new(ActiveRecord::Migration[8.1]).new
    expect(migration.compatibility_behavior).to be_a oracle_behavior::V8_1
  end

  it "gives a running Migration[8.2] the no-op base behavior through the Rails hook" do
    migration = Class.new(ActiveRecord::Migration[8.2]).new
    expect(migration.compatibility_behavior).to be_an_instance_of ActiveRecord::Migration::CompatibilityBehavior
  end
end

RSpec.describe "migration compatibility for identity primary keys" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    @oracle12c_or_higher = @conn.database_version >= "12"
  end

  after(:each) do
    ActiveRecord::Migration.suppress_messages do
      schema_define do
        drop_table :test_identity_pks, if_exists: true
        drop_table :test_identity_pks_composite, if_exists: true
        drop_table :test_identity_pks_no_id, if_exists: true
      end
    end
    @conn.schema_cache.clear!
  end

  def run_migration(version, &block)
    migration = Class.new(ActiveRecord::Migration[version]) do
      define_method(:change, &block)
    end.new

    ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
  end

  def sequence_exists?(name)
    @conn.select_value(<<~SQL.squish, "SCHEMA").present?
      SELECT 1 FROM user_sequences WHERE sequence_name = '#{name.to_s.upcase}' AND ROWNUM = 1
    SQL
  end

  def identity_column_exists?(table_name, column_name)
    @conn.select_value(<<~SQL.squish, "SCHEMA").present?
      SELECT 1 FROM user_tab_identity_cols
       WHERE table_name = '#{table_name.to_s.upcase}'
         AND column_name = '#{column_name.to_s.upcase}'
         AND ROWNUM = 1
    SQL
  end

  context "on Oracle 12.1 or higher" do
    before do
      skip "requires Oracle 12.1+" unless @oracle12c_or_higher
    end

    describe "Migration[8.2]+ default behavior" do
      it "creates an identity primary key by default" do
        run_migration(8.2) { create_table :test_identity_pks }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "honors per-table opt-out via identity: false" do
        run_migration(8.2) { create_table :test_identity_pks, identity: false }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "skips prefetch_primary_key? for the identity table" do
        run_migration(8.2) { create_table :test_identity_pks }

        expect(@conn.prefetch_primary_key?(:test_identity_pks)).to be false
      end

      it "skips auto-injection when id: false is passed" do
        run_migration(8.2) do
          create_table :test_identity_pks_no_id, id: false do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks_no_id, :id)).to be false
      end

      it "skips auto-injection when id: :integer is passed" do
        run_migration(8.2) do
          create_table :test_identity_pks, id: :integer do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "skips auto-injection when a composite primary key is passed" do
        run_migration(8.2) do
          create_table :test_identity_pks_composite, primary_key: [:a, :b] do |t|
            t.integer :a
            t.integer :b
          end
        end

        expect(identity_column_exists?(:test_identity_pks_composite, :a)).to be false
        expect(identity_column_exists?(:test_identity_pks_composite, :b)).to be false
      end
    end

    describe "Migration[8.2]+ on other create_table forms" do
      it "creates an identity primary key on a table with primary_key: \"code\"" do
        run_migration(8.2) { create_table :test_identity_pks, primary_key: "code" }

        expect(identity_column_exists?(:test_identity_pks, :code)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "creates an identity primary key on a temporary table" do
        run_migration(8.2) { create_table :test_identity_pks, temporary: true }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "leaves create_join_table without a primary key, a sequence or an identity column" do
        run_migration(8.2) { create_join_table :cats, :dogs }

        expect(@conn.primary_key("cats_dogs")).to be_nil
        expect(sequence_exists?(:cats_dogs_seq)).to be false
        expect(identity_column_exists?(:cats_dogs, :id)).to be false
      ensure
        schema_define { drop_table :cats_dogs, if_exists: true }
      end
    end

    describe "Migration[8.1] (per-migration opt-out)" do
      it "creates a sequence-backed primary key by default" do
        run_migration(8.1) { create_table :test_identity_pks }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "still honors explicit identity: true (DB-supported)" do
        run_migration(8.1) { create_table :test_identity_pks, identity: true }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "migrates a change migration down again, dropping the table and its sequence" do
        migration = Class.new(ActiveRecord::Migration[8.1]) do
          def change
            create_table :test_identity_pks do |t|
              t.string :name
            end
          end
        end

        ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
        expect(sequence_exists?(:test_identity_pks_seq)).to be true

        ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
        expect(@conn.table_exists?(:test_identity_pks)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end
    end

    describe "Migration[7.0] (older versions)" do
      it "creates a sequence-backed primary key by default" do
        run_migration(7.0) { create_table :test_identity_pks }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end
    end

    describe "Schema.define / direct connection.create_table" do
      it "creates an identity primary key by default (no migration version context)" do
        schema_define do
          create_table :test_identity_pks do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "honors explicit identity: false" do
        schema_define do
          create_table :test_identity_pks, identity: false do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "creates an identity primary key when loading a versioned ActiveRecord::Schema[8.2] dump" do
        ActiveRecord::Migration.suppress_messages do
          ActiveRecord::Schema[8.2].define do
            create_table :test_identity_pks, force: true do |t|
              t.string :name
            end
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "keeps the sequence default when loading a versioned ActiveRecord::Schema[8.1] dump" do
        ActiveRecord::Migration.suppress_messages do
          ActiveRecord::Schema[8.1].define do
            create_table :test_identity_pks, force: true do |t|
              t.string :name
            end
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end
    end

    describe "schema dump and reload" do
      def dump_tables(tables)
        stream = StringIO.new
        ActiveRecord.schema_ignored_tables = @conn.data_sources - tables
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
        stream.string
      ensure
        ActiveRecord.schema_ignored_tables = []
      end

      it "reloads a dump of mixed primary key kinds to the same dump" do
        tables = %w[test_identity_pks test_identity_pks_seq_backed test_identity_pks_code test_identity_pks_triggered]
        schema_define do
          create_table :test_identity_pks do |t|
            t.string :name
          end
          create_table :test_identity_pks_seq_backed, identity: false do |t|
            t.string :name
          end
          create_table :test_identity_pks_code, primary_key: "code" do |t|
            t.string :name
          end
          create_table :test_identity_pks_triggered, primary_key_trigger: true do |t|
            t.string :name
          end
        end

        first = dump_tables(tables)
        expect(first).to include('create_table "test_identity_pks", force: :cascade')
        expect(first).to include('create_table "test_identity_pks_seq_backed", identity: false')
        expect(first).to include('create_table "test_identity_pks_code", primary_key: "code"')
        expect(first).to include('create_table "test_identity_pks_triggered", primary_key_trigger: true')

        schema_define { tables.each { |table| drop_table table } }
        # Load without the version so schema_migrations is left untouched.
        ActiveRecord::Migration.suppress_messages { eval(first.sub(/define\(version: [^)]*\)/, "define")) }
        second = dump_tables(tables)

        expect(second).to eq first
        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(identity_column_exists?(:test_identity_pks_code, :code)).to be true
        expect(identity_column_exists?(:test_identity_pks_seq_backed, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq_backed_seq)).to be true
      ensure
        schema_define do
          %w[test_identity_pks_seq_backed test_identity_pks_code test_identity_pks_triggered].each do |table|
            drop_table table, if_exists: true
          end
        end
      end
    end

    describe "Migration[8.2]+ with explicit Oracle sequence options" do
      it "treats sequence_name: as opt-out of the identity default" do
        run_migration(8.2) do
          create_table :test_identity_pks, sequence_name: "explicit_seq" do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?("explicit_seq")).to be true
      ensure
        @conn.execute("DROP SEQUENCE explicit_seq") rescue nil
      end

      it "treats sequence_start_value: as opt-out of the identity default" do
        run_migration(8.2) do
          create_table :test_identity_pks, sequence_start_value: 10000 do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "treats primary_key_trigger: true as opt-out of the identity default" do
        run_migration(8.2) do
          create_table :test_identity_pks, primary_key_trigger: true do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end
    end
  end

  context "on Oracle below 12.1" do
    before do
      skip "applies only to Oracle versions before 12.1" if @oracle12c_or_higher
    end

    it "Migration[8.2]+ falls back to sequence (auto-inject is gated by supports_identity_columns?)" do
      run_migration(8.2) { create_table :test_identity_pks }

      expect(sequence_exists?(:test_identity_pks_seq)).to be true
    end

    it "Migration[8.2]+ with explicit identity: true raises ArgumentError" do
      expect {
        run_migration(8.2) { create_table :test_identity_pks, identity: true }
      }.to raise_error(ArgumentError, /Oracle Database 12\.1 or higher/)
    end
  end
end

RSpec.describe "OracleEnhanced::CompatibilityBehavior for add_index unique: true" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  before(:each) do
    schema_define do
      create_table :test_compat_warn, force: true do |t|
        t.string :first_name
      end
    end
  end

  after(:each) do
    schema_define do
      drop_table :test_compat_warn, if_exists: true
    end
  end

  def migrate_up(migration_class, &body)
    klass = Class.new(migration_class) do
      define_method(:change, &body)
    end
    klass.migrate(:up)
  end

  describe "Migration[8.2] (current default — Phase 2)" do
    it "does not create an implicit UNIQUE constraint and does not warn" do
      expect {
        migrate_up(ActiveRecord::Migration[8.2]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v82
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v82")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_v82")
    end

    it "does not create the implicit constraint for inline t.index :col, unique: true" do
      migrate_up(ActiveRecord::Migration[8.2]) do
        create_table :test_v82_inline, force: true do |t|
          t.string :name
          t.index :name, unique: true, name: :uniq_v82_inline
        end
      end

      expect(@conn.indexes(:test_v82_inline).map(&:name)).to include("uniq_v82_inline")
      expect(@conn.unique_constraints(:test_v82_inline).map(&:name)).not_to include("uniq_v82_inline")
    ensure
      schema_define { drop_table :test_v82_inline, if_exists: true }
    end

    it "does not create the implicit constraint for inline t.index inside change_table" do
      expect {
        migrate_up(ActiveRecord::Migration[8.2]) do
          change_table :test_compat_warn do |t|
            t.index :first_name, unique: true, name: :uniq_v82_chg
          end
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v82_chg")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_v82_chg")
    end

    it "does not create the implicit constraint for add_reference index: { unique: true }" do
      expect {
        migrate_up(ActiveRecord::Migration[8.2]) do
          add_reference :test_compat_warn, :author, index: { unique: true, name: :uniq_v82_ref }
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v82_ref")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_v82_ref")
    end
  end

  describe "Migration[8.1] (pre-8.2 — V8_1 behavior preserves the implicit-constraint default)" do
    it "creates the implicit UNIQUE constraint and emits the deprecation warning" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v81
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81")
    end

    it "creates the implicit constraint for inline t.index :col, unique: true" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          create_table :test_v81_inline, force: true do |t|
            t.string :name
            t.index :name, unique: true, name: :uniq_v81_inline
          end
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_v81_inline).map(&:name)).to include("uniq_v81_inline")
      expect(@conn.unique_constraints(:test_v81_inline).map(&:name)).to include("uniq_v81_inline")
    ensure
      schema_define { drop_table :test_v81_inline, if_exists: true }
    end

    it "creates the implicit constraint for inline t.index inside change_table" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          change_table :test_compat_warn do |t|
            t.index :first_name, unique: true, name: :uniq_v81_chg
          end
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81_chg")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81_chg")
    end

    it "creates the implicit constraint for add_reference index: { unique: true }" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          add_reference :test_compat_warn, :author, index: { unique: true, name: :uniq_v81_ref }
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81_ref")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81_ref")
    end

    it "creates the implicit constraint for t.references index: { unique: true } inside change_table" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          change_table :test_compat_warn do |t|
            t.references :editor, index: { unique: true, name: :uniq_v81_chg_ref }
          end
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81_chg_ref")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81_chg_ref")
    end

    it "creates the implicit constraint for inline t.index inside create_join_table" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          create_join_table :apples, :pears do |t|
            t.index :apple_id, unique: true, name: :uniq_v81_join
          end
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:apples_pears).map(&:name)).to include("uniq_v81_join")
      expect(@conn.unique_constraints(:apples_pears).map(&:name)).to include("uniq_v81_join")
    ensure
      schema_define { drop_table :apples_pears, if_exists: true }
    end

    it "reverts a change migration cleanly (the flag reaches remove_index/drop_table via inversion)" do
      migration = Class.new(ActiveRecord::Migration[8.1]) do
        def change
          create_table :test_v81_revert, force: true do |t|
            t.string :name
          end
          add_index :test_v81_revert, :name, unique: true, name: :uniq_v81_revert
        end
      end

      deprecator = ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator
      deprecator.silence { migration.migrate(:up) }
      expect(@conn.unique_constraints(:test_v81_revert).map(&:name)).to include("uniq_v81_revert")

      expect {
        deprecator.silence { migration.migrate(:down) }
      }.not_to raise_error
      expect(@conn.table_exists?(:test_v81_revert)).to be false
    ensure
      schema_define { drop_table :test_v81_revert, if_exists: true }
    end
  end

  describe "Migration[7.0] (resolves to the V8_1 behavior, below the 8.1 boundary)" do
    it "creates the implicit UNIQUE constraint and emits the deprecation warning" do
      expect {
        migrate_up(ActiveRecord::Migration[7.0]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v70
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v70")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v70")
    end
  end

  describe "the add_index_unique_creates_constraint setting" do
    around(:each) do |example|
      adapter = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
      previous = adapter.add_index_unique_creates_constraint
      example.run
    ensure
      adapter.add_index_unique_creates_constraint = previous
    end

    it "creates the implicit constraint when the flag is true even under Migration[8.2]" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true

      expect {
        migrate_up(ActiveRecord::Migration[8.2]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_flag_override
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_flag_override")
    end

    it "creates no constraint and does not warn when the setting is false, even under Migration[8.1]" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = false

      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_flag_off
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_flag_off")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_flag_off")
    end
  end

  describe "Migration[8.1] on the remaining create and change forms" do
    # These examples check the constraint, not the warning that comes with it.
    around(:each) do |example|
      ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence { example.run }
    end

    after(:each) do
      schema_define do
        drop_table :test_cw, if_exists: true
        drop_table :test_cw_join, if_exists: true
      end
    end

    it "names the constraint after the index when add_index has no name" do
      migrate_up(ActiveRecord::Migration[8.1]) do
        add_index :test_compat_warn, :first_name, unique: true
      end

      index_name = @conn.indexes(:test_compat_warn).detect(&:unique).name
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include(index_name)
    end

    it "creates the constraint for t.references index: { unique: true } inside create_table" do
      migrate_up(ActiveRecord::Migration[8.1]) do
        create_table :test_cw do |t|
          t.references :author, index: { unique: true }
        end
      end

      index_name = @conn.indexes(:test_cw).detect(&:unique).name
      expect(@conn.unique_constraints(:test_cw).map(&:name)).to include(index_name)
    end

    it "uses the Rails index name for a polymorphic add_reference" do
      migrate_up(ActiveRecord::Migration[8.1]) do
        create_table :test_cw
        add_reference :test_cw, :author, polymorphic: true, index: { unique: true }
      end

      expect(@conn.indexes(:test_cw).map(&:name)).to include("index_test_cw_on_author")
      expect(@conn.unique_constraints(:test_cw).map(&:name)).to include("index_test_cw_on_author")
    end

    it "uses the Rails index name for a polymorphic t.references inside change_table" do
      migrate_up(ActiveRecord::Migration[8.1]) do
        create_table :test_cw
        change_table :test_cw do |t|
          t.references :owner, polymorphic: true, index: { unique: true }
        end
      end

      expect(@conn.unique_constraints(:test_cw).map(&:name)).to include("index_test_cw_on_owner")
    end

    it "skips the constraint together with an existing index on add_index if_not_exists: true" do
      migration = Class.new(ActiveRecord::Migration[8.1]) do
        def change
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v81_ine, if_not_exists: true
        end
      end

      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
      expect { ActiveRecord::Migration.suppress_messages { migration.migrate(:up) } }.not_to raise_error

      expect(@conn.unique_constraints(:test_compat_warn).map(&:name).count("uniq_v81_ine")).to eq 1
    end

    it "leaves an existing table alone on create_table if_not_exists: true" do
      expect {
        migrate_up(ActiveRecord::Migration[8.1]) do
          create_table :test_compat_warn, if_not_exists: true do |t|
            t.string :extra
            t.index :extra, unique: true, name: :uniq_v81_ine_tbl
          end
        end
      }.not_to raise_error

      expect(@conn.columns(:test_compat_warn).map(&:name)).not_to include("extra")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_v81_ine_tbl")
    end

    it "applies table_name_prefix to the constraint" do
      ActiveRecord::Base.table_name_prefix = "pre_"
      migrate_up(ActiveRecord::Migration[8.1]) do
        create_table :cw_prefixed do |t|
          t.string :code
        end
        add_index :cw_prefixed, :code, unique: true, name: :uniq_v81_pre
      end

      expect(@conn.unique_constraints("pre_cw_prefixed").map(&:name)).to include("uniq_v81_pre")
    ensure
      ActiveRecord::Base.table_name_prefix = ""
      @conn.drop_table "pre_cw_prefixed", if_exists: true
    end

    it "migrates change_table { t.index } and { t.references } down again" do
      migration = Class.new(ActiveRecord::Migration[8.1]) do
        def change
          create_table :test_cw do |t|
            t.string :code
          end
          change_table :test_cw do |t|
            t.index :code, unique: true, name: :uniq_v81_chg_down
            t.references :author, index: { unique: true, name: :uniq_v81_ref_down }
          end
        end
      end

      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
      expect(@conn.unique_constraints(:test_cw).map(&:name)).to include("uniq_v81_chg_down", "uniq_v81_ref_down")

      expect { ActiveRecord::Migration.suppress_messages { migration.migrate(:down) } }.not_to raise_error
      expect(@conn.table_exists?(:test_cw)).to be false
    end
  end

  describe "Migration[8.2] on the remaining create and change forms" do
    after(:each) do
      schema_define do
        drop_table :test_cw, if_exists: true
        drop_table :test_cw_join, if_exists: true
      end
    end

    it "creates no constraint for inline t.index inside create_join_table" do
      expect {
        migrate_up(ActiveRecord::Migration[8.2]) do
          create_join_table :cats, :dogs, table_name: :test_cw_join do |t|
            t.index :cat_id, unique: true, name: :uniq_v82_join
          end
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_cw_join).map(&:name)).not_to include("uniq_v82_join")
    end

    it "creates no constraint for t.references index: { unique: true } inside change_table" do
      migrate_up(ActiveRecord::Migration[8.2]) do
        create_table :test_cw
        change_table :test_cw do |t|
          t.references :author, index: { unique: true, name: :uniq_v82_chg_ref }
        end
      end

      expect(@conn.indexes(:test_cw).map(&:name)).to include("uniq_v82_chg_ref")
      expect(@conn.unique_constraints(:test_cw).map(&:name)).not_to include("uniq_v82_chg_ref")
    end
  end

  describe "schema loads" do
    after(:each) do
      schema_define { drop_table :test_cw, if_exists: true }
    end

    it "replays an ActiveRecord::Schema[8.1] file as written, with the constraint and the warning" do
      expect {
        ActiveRecord::Migration.suppress_messages do
          ActiveRecord::Schema[8.1].define do
            create_table :test_cw, force: true do |t|
              t.string :code
              t.index :code, unique: true, name: :uniq_s81
            end
          end
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_cw).map(&:name)).to include("uniq_s81")
    end

    it "creates no constraint from an ActiveRecord::Schema[8.2] file" do
      expect {
        ActiveRecord::Migration.suppress_messages do
          ActiveRecord::Schema[8.2].define do
            create_table :test_cw, force: true do |t|
              t.string :code
              t.index :code, unique: true, name: :uniq_s82
            end
          end
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_cw).map(&:name)).to include("uniq_s82")
      expect(@conn.unique_constraints(:test_cw).map(&:name)).not_to include("uniq_s82")
    end
  end
end
