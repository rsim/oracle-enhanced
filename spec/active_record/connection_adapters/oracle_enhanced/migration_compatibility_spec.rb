# frozen_string_literal: true

RSpec.describe "OracleEnhanced::CompatibilityBehavior resolution" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  def oracle_behavior
    ActiveRecord::ConnectionAdapters::OracleEnhanced::CompatibilityBehavior
  end

  it "resolves Migration[8.2] to V8_2" do
    expect(@conn.compatibility_behavior_for(ActiveRecord::Migration[8.2])).to eq oracle_behavior::V8_2
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
