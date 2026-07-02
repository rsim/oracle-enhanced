# frozen_string_literal: true

RSpec.describe "migration compatibility for identity primary keys" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
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
    end

    describe "Migration[7.0] (older versions)" do
      it "creates a sequence-backed primary key by default" do
        run_migration(7.0) { create_table :test_identity_pks }

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end
    end

    describe "Schema.define / direct connection.create_table" do
      it "creates a sequence-backed primary key by default (no migration version context)" do
        schema_define do
          create_table :test_identity_pks do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
      end

      it "still honors explicit identity: true" do
        schema_define do
          create_table :test_identity_pks, identity: true do |t|
            t.string :name
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be true
        expect(sequence_exists?(:test_identity_pks_seq)).to be false
      end

      it "keeps the sequence default when loading a versioned ActiveRecord::Schema[8.2] dump" do
        ActiveRecord::Migration.suppress_messages do
          ActiveRecord::ConnectionAdapters::OracleEnhanced.deprecator.silence do
            ActiveRecord::Schema[8.2].define do
              create_table :test_identity_pks, force: true do |t|
                t.string :name
              end
            end
          end
        end

        expect(identity_column_exists?(:test_identity_pks, :id)).to be false
        expect(sequence_exists?(:test_identity_pks_seq)).to be true
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

  def run_migration(migration_class, &body)
    klass = Class.new(migration_class) do
      define_method(:change, &body)
    end
    klass.migrate(:up)
  end

  describe "Migration[8.2] (current default — Phase 2)" do
    it "does not create an implicit UNIQUE constraint and does not warn" do
      expect {
        run_migration(ActiveRecord::Migration[8.2]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v82
        end
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v82")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).not_to include("uniq_v82")
    end

    it "does not create the implicit constraint for inline t.index :col, unique: true" do
      run_migration(ActiveRecord::Migration[8.2]) do
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
        run_migration(ActiveRecord::Migration[8.2]) do
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
        run_migration(ActiveRecord::Migration[8.2]) do
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
        run_migration(ActiveRecord::Migration[8.1]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v81
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81")
    end

    it "creates the implicit constraint for inline t.index :col, unique: true" do
      expect {
        run_migration(ActiveRecord::Migration[8.1]) do
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
        run_migration(ActiveRecord::Migration[8.1]) do
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
        run_migration(ActiveRecord::Migration[8.1]) do
          add_reference :test_compat_warn, :author, index: { unique: true, name: :uniq_v81_ref }
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v81_ref")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v81_ref")
    end

    it "creates the implicit constraint for t.references index: { unique: true } inside change_table" do
      expect {
        run_migration(ActiveRecord::Migration[8.1]) do
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
        run_migration(ActiveRecord::Migration[8.1]) do
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
        run_migration(ActiveRecord::Migration[7.0]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_v70
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.indexes(:test_compat_warn).map(&:name)).to include("uniq_v70")
      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_v70")
    end
  end

  describe "explicit global flag overrides Migration[8.2] default" do
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
        run_migration(ActiveRecord::Migration[8.2]) do
          add_index :test_compat_warn, :first_name, unique: true, name: :uniq_flag_override
        end
      }.to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_compat_warn).map(&:name)).to include("uniq_flag_override")
    end
  end
end
