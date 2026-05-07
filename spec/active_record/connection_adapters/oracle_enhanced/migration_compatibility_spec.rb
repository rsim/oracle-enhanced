# frozen_string_literal: true

describe "OracleEnhanced::MigrationCompatibility for add_index unique: true" do
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
  end

  describe "Migration[8.1] (legacy — V8_1 module preserves implicit-constraint default)" do
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
