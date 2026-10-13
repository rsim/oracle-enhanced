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
