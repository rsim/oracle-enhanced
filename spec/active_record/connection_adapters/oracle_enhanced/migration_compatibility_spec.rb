# frozen_string_literal: true

describe "migration compatibility for identity primary keys" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @oracle12c_or_higher = @conn.database_version.first >= 12
  end

  after(:each) do
    ActiveRecord::Migration.suppress_messages do
      schema_define do
        drop_table :test_identity_pks, if_exists: true
        drop_table :test_identity_pks_uuid, if_exists: true
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

    describe "Schema.define / direct connection.create_table (no gating)" do
      it "creates a sequence-backed primary key (no auto-injection)" do
        schema_define do
          create_table :test_identity_pks do |t|
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
