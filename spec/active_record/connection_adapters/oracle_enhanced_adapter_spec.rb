# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter" do
  include LoggerSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  describe "cache table columns" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.string  :first_name, limit: 20
          t.string  :last_name, limit: 25
          if ActiveRecord::Base.lease_connection.supports_virtual_columns?
            t.virtual :full_name, as: "(first_name || ' ' || last_name)"
          else
            t.string  :full_name, limit: 46
          end
          t.date    :hire_date
        end
      end
      schema_define do
        create_table :test_employees_without_pk, id: false, force: true do |t|
          t.string  :first_name, limit: 20
          t.string  :last_name, limit: 25
          t.date    :hire_date
        end
      end
      @column_names = ["id", "first_name", "last_name", "full_name", "hire_date"]
      @column_sql_types = ["NUMBER(38)", "VARCHAR2(20)", "VARCHAR2(25)", "VARCHAR2(46)", "DATE"]
      class ::TestEmployee < ActiveRecord::Base
      end
      # Another class using the same table
      class ::TestEmployee2 < ActiveRecord::Base
        self.table_name = "test_employees"
      end
    end

    after(:all) do
      @conn = ActiveRecord::Base.lease_connection
      Object.send(:remove_const, "TestEmployee")
      Object.send(:remove_const, "TestEmployee2")
      @conn.drop_table :test_employees, if_exists: true
      @conn.drop_table :test_employees_without_pk, if_exists: true
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
      @conn = ActiveRecord::Base.lease_connection
    end

    after(:each) do
      clear_logger
    end

    describe "without column caching" do
      it "should identify virtual columns as such" do
        skip "Not supported in this database version" unless @conn.supports_virtual_columns?
        te = TestEmployee.lease_connection.columns("test_employees").detect(&:virtual?)
        expect(te.name).to eq("full_name")
      end

      it "should get columns from database at first time" do
        @conn.clear_table_caches(:test_employees)
        expect(TestEmployee.lease_connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).join("\n")).to match(/select .* from all_tab_cols/im)
      end

      it "should not get columns from database at second time" do
        TestEmployee.lease_connection.columns("test_employees")
        @logger.clear(:debug)
        expect(TestEmployee.lease_connection.columns("test_employees").map(&:name)).to eq(@column_names)
        expect(@logger.logged(:debug).join("\n")).not_to match(/select .* from all_tab_cols/im)
      end

      it "should get primary key from database at first time" do
        expect(TestEmployee.lease_connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should get primary key from database at second time without query" do
        expect(TestEmployee.lease_connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        @logger.clear(:debug)
        expect(TestEmployee.lease_connection.pk_and_sequence_for("test_employees")).to eq(["id", "test_employees_seq"])
        expect(@logger.logged(:debug).last).to match(/select .* from all_constraints/im)
      end

      it "should have correct sql types when 2 models are using the same table and AR query cache is enabled" do
        @conn.cache do
          expect(TestEmployee.columns.map(&:sql_type)).to eq(@column_sql_types)
          expect(TestEmployee2.columns.map(&:sql_type)).to eq(@column_sql_types)
        end
      end

      it "should get sequence value at next time" do
        TestEmployee.create!
        expect(@logger.logged(:debug).first).not_to match(/SELECT "TEST_EMPLOYEES_SEQ".NEXTVAL FROM dual/im)
        @logger.clear(:debug)
        TestEmployee.create!
        expect(@logger.logged(:debug).first).to match(/SELECT "TEST_EMPLOYEES_SEQ".NEXTVAL FROM dual/im)
      end
    end
  end

  describe "deprecated clear_table_columns_cache" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
    end

    it "warns and forwards to clear_table_caches" do
      expect(@conn).to receive(:clear_table_caches).with(:test_employees)
      expect {
        @conn.clear_table_columns_cache(:test_employees)
      }.to output(/clear_table_columns_cache is deprecated.*activerecord-oracle_enhanced-adapter.*a future version/m).to_stderr
    end
  end

  describe "supports_insert_returning?" do
    it "is true" do
      expect(ActiveRecord::Base.lease_connection.supports_insert_returning?).to be(true)
    end

    # `RETURNING ... INTO :bind` path: triggered when the PK is database-assigned
    # at INSERT time (IDENTITY column on Oracle 12.1+).
    context "with an IDENTITY primary key" do
      before(:all) do
        skip "Not supported in this database version" unless ActiveRecord::Base.lease_connection.supports_identity_columns?
        schema_define do
          create_table :test_returning_identity_items, force: true, identity: true do |t|
            t.string :name
          end
        end
        class ::TestReturningIdentityItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define { drop_table :test_returning_identity_items, if_exists: true }
        Object.send(:remove_const, "TestReturningIdentityItem") if defined?(TestReturningIdentityItem)
        ActiveRecord::Base.clear_cache!
      end

      before(:each) { set_logger }

      after(:each) do
        clear_logger
        TestReturningIdentityItem.delete_all
      end

      it "returns the database-assigned primary key from Model.create!" do
        record = TestReturningIdentityItem.create!(name: "alpha")
        expect(record.id).to be_a(Integer)
        expect(record.id).to be > 0
      end

      it "emits Oracle's `RETURNING ... INTO :bind` form (not the PG-style `RETURNING col`)" do
        TestReturningIdentityItem.create!(name: "alpha")
        insert_log = @logger.logged(:debug).find { |line| line.include?("INSERT INTO") && line.include?("TEST_RETURNING_IDENTITY_ITEMS") }
        expect(insert_log).not_to be_nil, "INSERT statement was not logged"
        expect(insert_log).to match(/RETURNING\s+"ID"\s+INTO\s+:returning_id/i)
        expect(insert_log).not_to match(/RETURNING\s+"ID"\s*\)?\s*\z/i)
      end

      # AbstractAdapter#sql_for_insert infers the primary key from the SQL when
      # the caller passes pk: nil. Generic callers that go through this path
      # without an explicit `pk` used to miss out on RETURNING auto-fetch on
      # Oracle because the fallback was not mirrored locally; this spec locks
      # in the parity introduced for issue #2732.
      it "infers the primary key from the SQL when pk: nil (parity with AbstractAdapter)" do
        conn = ActiveRecord::Base.lease_connection
        insert_sql = "INSERT INTO #{conn.quote_table_name('test_returning_identity_items')} (#{conn.quote_column_name('name')}) VALUES ('direct-call')"
        out_sql, out_binds = conn.send(:sql_for_insert, insert_sql, nil, [], nil)
        expect(out_sql).to match(/RETURNING\s+"ID"\s+INTO\s+:returning_id/i)
        expect(out_binds.last.name).to eq("returning_id")
      end
    end

    # Sequence-prefetched path: oracle-enhanced's default for `create_table` (no
    # `identity: true`). The PK is fetched via `seq.NEXTVAL` before the INSERT
    # and bound into the values list, so RETURNING is NOT used. This spec locks
    # in that the flag flip + super-skip does not accidentally inject a RETURNING
    # clause on this path.
    context "with a sequence-prefetched primary key" do
      before(:all) do
        schema_define do
          create_table :test_returning_seq_items, force: true do |t|
            t.string :name
          end
        end
        class ::TestReturningSeqItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define { drop_table :test_returning_seq_items, if_exists: true }
        Object.send(:remove_const, "TestReturningSeqItem") if defined?(TestReturningSeqItem)
        ActiveRecord::Base.clear_cache!
      end

      before(:each) { set_logger }

      after(:each) do
        clear_logger
        TestReturningSeqItem.delete_all
      end

      it "returns the sequence-fetched primary key from Model.create!" do
        record = TestReturningSeqItem.create!(name: "alpha")
        expect(record.id).to be_a(Integer)
        expect(record.id).to be > 0
      end

      it "binds the sequence-fetched id into the INSERT and does NOT emit RETURNING" do
        TestReturningSeqItem.create!(name: "alpha")
        insert_log = @logger.logged(:debug).find { |line| line.include?("INSERT INTO") && line.include?("TEST_RETURNING_SEQ_ITEMS") }
        expect(insert_log).not_to be_nil, "INSERT statement was not logged"
        expect(insert_log).to match(/INSERT INTO "TEST_RETURNING_SEQ_ITEMS".*"ID"/im)
        # \bRETURNING\b\s+(?:"|INTO) catches the SQL keyword followed by either
        # a quoted column or `INTO :bind`; avoids false matches on the table
        # name (which contains the substring "RETURNING").
        expect(insert_log).not_to match(/\bRETURNING\b\s+(?:"|INTO\b)/i)
      end
    end
  end

  describe "session information" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
    end

    it "should get current database name" do
      # get database name if using //host:port/database connection string
      database_name = CONNECTION_PARAMS[:database].split("/").last
      expect(@conn.current_database.upcase).to eq(database_name.upcase)
    end

    it "should get current database session user" do
      expect(@conn.current_user.upcase).to eq(CONNECTION_PARAMS[:username].upcase)
    end
  end

  describe "temporary tables" do
    before(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:table] = "UNUSED"
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = "UNUSED"
      @conn = ActiveRecord::Base.lease_connection
    end

    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces = {}
    end

    after(:each) do
      @conn.drop_table :foos, if_exists: true
    end

    it "should create ok" do
      @conn.create_table :foos, temporary: true, id: false do |t|
        t.integer :id
        t.text :bar
      end
    end
    it "should show up as temporary" do
      @conn.create_table :foos, temporary: true, id: false do |t|
        t.integer :id
      end
      expect(@conn.temporary_table?("foos")).to be_truthy
    end
  end

  describe "`has_many` assoc has `dependent: :delete_all` with `order`" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string      :title
        end
        create_table :test_comments do |t|
          t.integer     :test_post_id
          t.string      :description
        end
        add_index :test_comments, :test_post_id
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments, -> { order(:id) }, dependent: :delete_all
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
      TestPost.transaction do
        post = TestPost.create!(title: "Title")
        TestComment.create!(test_post_id: post.id, description: "Description")
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      ActiveRecord::Base.clear_cache!
    end

    it "should not occur `ActiveRecord::StatementInvalid: OCIError: ORA-00907: missing right parenthesis`" do
      expect { TestPost.first.destroy }.not_to raise_error
    end
  end

  describe "eager loading" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string      :title
        end
        create_table :test_comments do |t|
          t.integer     :test_post_id
          t.string      :description
        end
        add_index :test_comments, :test_post_id
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
      @ids = (1..1010).to_a
      TestPost.transaction do
        @ids.each do |id|
          TestPost.create!(id: id, title: "Title #{id}")
          TestComment.create!(test_post_id: id, description: "Description #{id}")
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      ActiveRecord::Base.clear_cache!
    end

    it "should load included association with more than 1000 records" do
      posts = TestPost.includes(:test_comments).to_a
      expect(posts.size).to eq(@ids.size)
    end
  end

  describe "insert_all!" do
    # `insert_all!` with explicit IDs is the minimum-viable surface for Oracle:
    # `INSERT ALL` cannot consume sequence-via-trigger or IDENTITY auto-fill
    # (Oracle evaluates the underlying sequence once per statement on INSERT ALL,
    # causing ORA-00001), so callers must supply IDs in either schema. Auto-PK
    # injection is tracked as follow-up.
    shared_examples "insert_all! basics" do
      it "inserts multiple rows in a single INSERT ALL statement" do
        model.insert_all!([
          { id: 1, name: "alpha", qty: 1 },
          { id: 2, name: "beta", qty: 2 },
          { id: 3, name: "gamma", qty: 3 },
        ])
        rows = model.order(:qty).pluck(:name, :qty)
        expect(rows).to eq([["alpha", 1], ["beta", 2], ["gamma", 3]])
      end

      it "handles values containing parens and embedded single quotes" do
        model.insert_all!([
          { id: 1, name: "Hello (world)", qty: 10 },
          { id: 2, name: "O'Reilly's", qty: 20 },
        ])
        rows = model.order(:qty).pluck(:name)
        expect(rows).to eq(["Hello (world)", "O'Reilly's"])
      end

      it "returns an empty result because INSERT ALL cannot carry RETURNING" do
        result = model.insert_all!([{ id: 1, name: "alpha", qty: 1 }])
        expect(result.rows).to eq([])
      end

      it "returns an empty result even when `returning:` is explicitly requested" do
        result = model.insert_all!([{ id: 1, name: "alpha", qty: 1 }], returning: [:id])
        expect(result.rows).to eq([])
      end

      it "raises ActiveModel::UnknownAttributeError for unknown columns (parity with AR core)" do
        expect {
          model.insert_all!([{ id: 1, name: "alpha", qty: 1, bogus: 99 }])
        }.to raise_error(ActiveModel::UnknownAttributeError, /bogus/)
      end
    end

    context "with sequence-based PK" do
      before(:all) do
        schema_define do
          create_table :test_insert_all_items, force: true do |t|
            t.string :name
            t.integer :qty
          end
        end
        class ::TestInsertAllItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_insert_all_items, if_exists: true
        end
        Object.send(:remove_const, "TestInsertAllItem") if defined?(TestInsertAllItem)
        ActiveRecord::Base.clear_cache!
      end

      after(:each) { TestInsertAllItem.delete_all }

      let(:model) { TestInsertAllItem }

      include_examples "insert_all! basics"
    end

    context "with IDENTITY PK (Oracle 12.1+)" do
      before(:all) do
        skip "Not supported in this database version" unless ActiveRecord::Base.lease_connection.supports_identity_columns?
        schema_define do
          create_table :test_insert_all_identity_items, force: true, identity: true do |t|
            t.string :name
            t.integer :qty
          end
        end
        class ::TestInsertAllIdentityItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_insert_all_identity_items, if_exists: true
        end
        Object.send(:remove_const, "TestInsertAllIdentityItem") if defined?(TestInsertAllIdentityItem)
        ActiveRecord::Base.clear_cache!
      end

      after(:each) { TestInsertAllIdentityItem.delete_all }

      let(:model) { TestInsertAllIdentityItem }

      include_examples "insert_all! basics"
    end

    describe "on_duplicate via Oracle MERGE" do
      before(:all) do
        schema_define do
          create_table :test_merge_items, force: true do |t|
            t.string :name
            t.integer :qty
          end
        end
        class ::TestMergeItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_merge_items, if_exists: true
        end
        Object.send(:remove_const, "TestMergeItem") if defined?(TestMergeItem)
        ActiveRecord::Base.clear_cache!
      end

      after(:each) { TestMergeItem.delete_all }

      it "reports the three on_duplicate capability flags as true" do
        conn = ActiveRecord::Base.lease_connection
        expect(conn.supports_insert_on_duplicate_skip?).to be(true)
        expect(conn.supports_insert_on_duplicate_update?).to be(true)
        expect(conn.supports_insert_conflict_target?).to be(true)
      end

      it "skips rows whose unique_by conflicts with existing ones (insert_all default)" do
        TestMergeItem.insert_all!([{ id: 100, name: "anchor", qty: 5 }])
        TestMergeItem.insert_all(
          [{ id: 100, name: "skip-this", qty: 99 }, { id: 101, name: "new", qty: 1 }],
          unique_by: :id,
        )
        expect(TestMergeItem.find(100).name).to eq("anchor")
        expect(TestMergeItem.find(100).qty).to eq(5)
        expect(TestMergeItem.find(101).name).to eq("new")
      end

      it "updates matched rows and inserts the rest (upsert_all)" do
        TestMergeItem.insert_all!([{ id: 200, name: "anchor", qty: 5 }])
        TestMergeItem.upsert_all(
          [{ id: 200, name: "updated", qty: 99 }, { id: 201, name: "fresh", qty: 1 }],
          unique_by: :id,
        )
        expect(TestMergeItem.find(200).name).to eq("updated")
        expect(TestMergeItem.find(200).qty).to eq(99)
        expect(TestMergeItem.find(201).name).to eq("fresh")
      end

      # ORA-38104: a MERGE that lists an ON-clause column in WHEN MATCHED UPDATE
      # SET is rejected by Oracle. Confirm the builder strips the unique_by
      # column(s) from the UPDATE SET clause.
      it "excludes the unique_by column from WHEN MATCHED THEN UPDATE SET" do
        TestMergeItem.insert_all!([{ id: 300, name: "anchor", qty: 5 }])
        expect {
          TestMergeItem.upsert_all(
            [{ id: 300, name: "renamed", qty: 50 }],
            unique_by: :id,
          )
        }.not_to raise_error
        expect(TestMergeItem.find(300).name).to eq("renamed")
      end

      it "falls back to the primary key when unique_by is omitted" do
        TestMergeItem.insert_all!([{ id: 400, name: "anchor", qty: 5 }])
        TestMergeItem.upsert_all([{ id: 400, name: "updated", qty: 50 }])
        expect(TestMergeItem.find(400).name).to eq("updated")
      end

      it "preserves values containing parens and embedded single quotes" do
        TestMergeItem.upsert_all(
          [
            { id: 500, name: "Hello (world)", qty: 10 },
            { id: 501, name: "O'Reilly's", qty: 20 },
          ],
          unique_by: :id,
        )
        names = TestMergeItem.where(id: [500, 501]).order(:id).pluck(:name)
        expect(names).to eq(["Hello (world)", "O'Reilly's"])
      end
    end

    # Mirrors AR core PG/MySQL's `Builder#touch_model_timestamps_unless`:
    # `updated_at` is only bumped when a user-supplied column actually changes.
    # See #2755 for the implementation rationale.
    describe "on_duplicate via Oracle MERGE with timestamps" do
      before(:all) do
        schema_define do
          create_table :test_merge_ts_items, force: true do |t|
            t.string :name
            t.integer :qty
            t.timestamps
          end
        end
        class ::TestMergeTsItem < ActiveRecord::Base
        end
      end

      after(:all) do
        schema_define do
          drop_table :test_merge_ts_items, if_exists: true
        end
        Object.send(:remove_const, "TestMergeTsItem") if defined?(TestMergeTsItem)
        ActiveRecord::Base.clear_cache!
      end

      after(:each) { TestMergeTsItem.delete_all }

      it "keeps updated_at stable on an idempotent upsert_all" do
        TestMergeTsItem.upsert_all([{ id: 1, name: "alpha", qty: 1 }], unique_by: :id)
        before_ts = TestMergeTsItem.find(1).updated_at
        sleep 0.1  # advance wall clock past TIMESTAMP precision
        TestMergeTsItem.upsert_all([{ id: 1, name: "alpha", qty: 1 }], unique_by: :id)
        expect(TestMergeTsItem.find(1).updated_at).to eq(before_ts)
      end

      it "bumps updated_at when a non-key column changes" do
        TestMergeTsItem.upsert_all([{ id: 2, name: "alpha", qty: 1 }], unique_by: :id)
        before_ts = TestMergeTsItem.find(2).updated_at
        sleep 0.1
        TestMergeTsItem.upsert_all([{ id: 2, name: "beta", qty: 2 }], unique_by: :id)
        expect(TestMergeTsItem.find(2).updated_at).to be > before_ts
      end

      it "respects an explicit updated_at value supplied by the caller" do
        explicit = Time.utc(2020, 1, 1, 12, 0, 0)
        TestMergeTsItem.upsert_all(
          [{ id: 3, name: "alpha", qty: 1, updated_at: explicit }],
          unique_by: :id,
        )
        expect(TestMergeTsItem.find(3).updated_at.utc).to eq(explicit)
      end
    end

    # Unit-level coverage of the helper that bridges AR core's bundled
    # values_list to Oracle's per-row INSERT ALL form. Locks in the per-row
    # split shape and the value-quoting behavior so a regression in either
    # AR core's `Builder#values_list` coercion or Arel's
    # `ValuesList` visitor surfaces here rather than as a misleading
    # ORA-9999 from the DB.
    describe "compile_per_row_values" do
      before(:all) do
        schema_define do
          create_table :test_insert_all_items, force: true do |t|
            t.string :name
            t.integer :qty
          end
        end
        class ::TestInsertAllItem < ActiveRecord::Base
        end unless defined?(TestInsertAllItem)
      end

      after(:all) do
        schema_define do
          drop_table :test_insert_all_items, if_exists: true
        end
        Object.send(:remove_const, "TestInsertAllItem") if defined?(TestInsertAllItem)
        ActiveRecord::Base.clear_cache!
      end

      let(:conn) { ActiveRecord::Base.lease_connection }

      def builder_for(rows)
        insert_all = ActiveRecord::InsertAll.new(
          TestInsertAllItem.all, conn, rows, on_duplicate: :raise,
        )
        ActiveRecord::InsertAll::Builder.new(insert_all)
      end

      it "returns one VALUES (...) fragment per input row" do
        builder = builder_for([
          { id: 1, name: "alpha", qty: 10 },
          { id: 2, name: "beta", qty: 20 },
        ])
        rows = conn.send(:compile_per_row_values, builder)
        expect(rows).to eq([
          "VALUES (1, 'alpha', 10)",
          "VALUES (2, 'beta', 20)",
        ])
      end

      it "preserves embedded parens and quote-escapes single quotes" do
        builder = builder_for([
          { id: 1, name: "Hello (world)", qty: 10 },
          { id: 2, name: "O'Reilly's",    qty: 20 },
        ])
        rows = conn.send(:compile_per_row_values, builder)
        expect(rows).to eq([
          "VALUES (1, 'Hello (world)', 10)",
          "VALUES (2, 'O''Reilly''s', 20)",
        ])
      end
    end
  end

  describe "lists" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      @ids = (1..2010).to_a
      TestPost.transaction do
        @ids.each do |id|
          TestPost.create!(id: id, title: "Title #{id}")
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    ##
    # See this GitHub issue for an explanation of homogenous lists.
    # https://github.com/rails/rails/commit/72fd0bae5948c1169411941aeea6fef4c58f34a9
    it "should allow more than 1000 items in a list where the list is homogenous" do
      posts = TestPost.where(id: @ids).to_a
      expect(posts.size).to eq(@ids.size)
    end

    it "should allow more than 1000 items in a list where the list is non-homogenous" do
      posts = TestPost.where(id: [*@ids, nil]).to_a
      expect(posts.size).to eq(@ids.size)
    end

    # some frameworks like baby_squeel construct Arel objects directly
    it "should allow more than 1000 items using Arel::Nodes::In" do
      table = TestPost.arel_table
      in_node = Arel::Nodes::In.new(table[:id], @ids)
      query = table.where(in_node).project(Arel.star)

      sql = query.to_sql
      posts = TestPost.connection.select_all(sql).to_a
      expect(posts.size).to eq(@ids.size)

      # SQL contains multiple IN clauses (split due to 1000 limit)
      expect(sql.scan(/IN \(/).size).to be > 1
    end

    it "should allow more than 1000 items using Arel::Nodes::NotIn" do
      ids = @ids.dup
      non_not_in = ids.pop

      table = TestPost.arel_table
      not_in_node = Arel::Nodes::NotIn.new(table[:id], ids)
      query = table.where(not_in_node).project(Arel.star)

      sql = query.to_sql
      posts = TestPost.connection.select_all(sql).to_a

      expect(posts.size).to eq(1)
      expect(posts.first["id"]).to eq(non_not_in)

      # SQL contains multiple NOT IN clauses (split due to 1000 limit)
      expect(sql.scan(/NOT IN \(/).size).to be > 1
    end
  end

  describe "with statement pool" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS.merge(statement_limit: 3))
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
      @statements = @conn.instance_variable_get(:@statements)
    end

    before(:each) do
      @conn.clear_cache!
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should clear older cursors when statement limit is reached" do
      skip "applies only when prepared statements are enabled" unless @conn.prepared_statements?
      binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
      # free statement pool from dictionary selections  to ensure next selects will increase statement pool
      @statements.clear
      expect {
        4.times do |i|
          @conn.exec_query("SELECT * FROM test_posts WHERE #{i}=#{i} AND id = :id", "SQL", binds)
        end
      }.to change(@statements, :length).by(+3)
    end

    it "should cache UPDATE statements with bind variables" do
      skip "applies only when prepared statements are enabled" unless @conn.prepared_statements?
      expect {
        binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
        @conn.exec_query("UPDATE test_posts SET id = :id", "SQL", binds)
      }.to change(@statements, :length).by(+1)
    end

    it "should not cache UPDATE statements with bind variables when prepared_statements is false" do
      skip "applies only when prepared statements are disabled" if @conn.prepared_statements?
      expect {
        binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
        @conn.exec_query("UPDATE test_posts SET id = :id", "SQL", binds)
      }.not_to change(@statements, :length)
    end

    it "should not cache UPDATE statements without bind variables" do
      expect {
        @conn.exec_query("UPDATE test_posts SET id = 1", "SQL", [])
      }.not_to change(@statements, :length)
    end

    it "should deallocate cached cursors on reset!" do
      skip "applies only when prepared statements are enabled" unless @conn.prepared_statements?
      binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
      @conn.exec_query("SELECT * FROM test_posts WHERE id = :id", "SQL", binds)
      expect(@statements.length).to be > 0

      expect(@statements).to receive(:clear).at_least(:once).and_call_original
      @conn.reset!
      expect(@statements.length).to eq(0)
    end
  end

  describe "database_exists?" do
    it "should raise `NotImplementedError`" do
      expect {
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.database_exists?(CONNECTION_PARAMS)
      }.to raise_error(NotImplementedError)
    end
  end

  describe "explain" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should explain query" do
      explain = TestPost.where(id: 1).explain
      expect(explain.inspect).to include("Cost")
      expect(explain.inspect).to include("INDEX UNIQUE SCAN")
    end

    it "should explain query with binds" do
      binds = [ActiveRecord::Relation::QueryAttribute.new("id", 1, ActiveRecord::Type::OracleEnhanced::Integer.new)]
      explain = TestPost.where(id: binds).explain
      expect(explain.inspect).to include("Cost")
      expect(explain.inspect).to include("INDEX UNIQUE SCAN").or include("TABLE ACCESS FULL")
    end
  end

  describe "using offset and limit" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.integer   :sort_order
          t.string    :first_name, limit: 20
          t.string    :last_name, limit: 20
          t.timestamps
        end
      end
      @employee = Class.new(ActiveRecord::Base) do
        self.table_name = :test_employees
      end
      @employee.create!(sort_order: 1, first_name: "Peter",   last_name: "Parker")
      @employee.create!(sort_order: 2, first_name: "Tony",    last_name: "Stark")
      @employee.create!(sort_order: 3, first_name: "Steven",  last_name: "Rogers")
      @employee.create!(sort_order: 4, first_name: "Bruce",   last_name: "Banner")
      @employee.create!(sort_order: 5, first_name: "Natasha", last_name: "Romanova")
    end

    after(:all) do
      @conn.drop_table :test_employees, if_exists: true
    end

    after(:each) do
      ActiveRecord::Base.clear_cache!
    end

    it "should return n records with limit(n)" do
      expect(@employee.limit(3).to_a.size).to be(3)
    end

    it "should return less than n records with limit(n) if there exist less than n records" do
      expect(@employee.limit(10).to_a.size).to be(5)
    end

    it "should return the records starting from offset n with offset(n)" do
      expect(@employee.order(:sort_order).first.first_name).to eq("Peter")
      expect(@employee.order(:sort_order).offset(0).first.first_name).to eq("Peter")
      expect(@employee.order(:sort_order).offset(1).first.first_name).to eq("Tony")
      expect(@employee.order(:sort_order).offset(4).first.first_name).to eq("Natasha")
    end
  end

  describe "valid_type?" do
    before(:all) do
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        create_table :test_employees, force: true do |t|
          t.string :first_name, limit: 20
        end
      end
    end

    after(:all) do
      @conn.drop_table :test_employees, if_exists: true
    end

    it "returns true when passed a valid type" do
      column = @conn.columns("test_employees").find { |col| col.name == "first_name" }
      expect(@conn.valid_type?(column.type)).to be true
    end

    it "returns false when passed an invalid type" do
      expect(@conn.valid_type?(:foobar)).to be false
    end
  end

  describe "serialized column" do
    before(:all) do
      schema_define do
        create_table :test_serialized_columns do |t|
          t.text :serialized
        end
      end
      class ::TestSerializedColumn < ActiveRecord::Base
        serialize :serialized, type: Array
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_serialized_columns
      end
      Object.send(:remove_const, "TestSerializedColumn")
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "should serialize" do
      new_value = "new_value"
      serialized_column = TestSerializedColumn.new

      expect(serialized_column.serialized).to eq([])
      serialized_column.serialized << new_value
      expect(serialized_column.serialized).to eq([new_value])
      serialized_column.save
      expect(serialized_column.save!).to be(true)

      serialized_column.reload
      expect(serialized_column.serialized).to eq([new_value])
      serialized_column.serialized = []
      expect(serialized_column.save!).to be(true)
    end
  end

  describe "Binary lob column" do
    before(:all) do
      schema_define do
        create_table :test_binary_columns do |t|
          t.binary :attachment
        end
      end
      class ::TestBinaryColumn < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_binary_columns
      end
      Object.send(:remove_const, "TestBinaryColumn")
      ActiveRecord::Base.table_name_prefix = nil
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "should serialize with non UTF-8 data" do
      binary_value = +"Hello \x93\xfa\x96\x7b"
      binary_value.force_encoding "UTF-8"

      binary_column_object = TestBinaryColumn.new
      binary_column_object.attachment = binary_value

      expect(binary_column_object.save!).to be(true)
    end
  end

  describe "quoting" do
    before(:all) do
      schema_define do
        create_table :test_logs, force: true do |t|
          t.timestamp :send_time
        end
      end
      class TestLog < ActiveRecord::Base
        validates_uniqueness_of :send_time
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_logs
      end
      Object.send(:remove_const, "TestLog")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "should create records including Time"  do
      TestLog.create! send_time: Time.now + 1.seconds
      TestLog.create! send_time: Time.now + 2.seconds
      expect(TestLog.count).to eq 2
    end
  end

  describe "synonym_names" do
    before(:all) do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :comment
        end
        add_synonym :synonym_comments, :test_comments
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_comments
        remove_synonym :synonym_comments
      end
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    it "includes synonyms in data_source" do
      conn = ActiveRecord::Base.lease_connection
      expect(conn).to be_data_source_exists("synonym_comments")
      expect(conn.data_sources).to include("synonym_comments")
    end
  end

  describe "dictionary selects with bind variables" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts

        drop_table :users, if_exists: true
        create_table :users, force: true do |t|
          t.string :name
          t.integer :group_id
        end

        drop_table :groups, if_exists: true
        create_table :groups, force: true do |t|
          t.string :name
        end
      end

      class ::TestPost < ActiveRecord::Base
      end

      class User < ActiveRecord::Base
        belongs_to :group
      end

      class Group < ActiveRecord::Base
        has_one :user
      end
    end

    before(:each) do
      @conn.clear_cache!
      set_logger
    end

    after(:each) do
      clear_logger
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
        drop_table :users
        drop_table :groups
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should test table existence" do
      expect(@conn.table_exists?("TEST_POSTS")).to be true
      expect(@conn.table_exists?("NOT_EXISTING")).to be false
    end

    it "should return array from indexes with bind usage" do
       expect(@conn.indexes("TEST_POSTS").class).to eq Array
       expect(@logger.logged(:debug).last).to match(/:table_name/)
       expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_POSTS"\]/)
     end

    it "should return content from columns witt bind usage" do
      expect(@conn.columns("TEST_POSTS").length).to be > 0
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_POSTS"\]/)
    end

    it "should return pk and sequence from pk_and_sequence_for with bind usage" do
      expect(@conn.pk_and_sequence_for("TEST_POSTS").length).to eq 2
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_POSTS"\]/)
    end

    it "should return pk from primary_keys with bind usage" do
      expect(@conn.primary_keys("TEST_POSTS")).to eq ["id"]
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_POSTS"\]/)
    end

    it "should not raise missing IN/OUT parameter like issue 1678" do
      # "to_sql" enforces unprepared_statement including dictionary access SQLs
      expect { User.joins(:group).to_sql }.not_to raise_exception
    end

    it "should return false from temporary_table? with bind usage" do
      expect(@conn.temporary_table?("TEST_POSTS")).to be false
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_POSTS"\]/)
    end
  end

  describe "Transaction" do
    before(:all) do
      schema_define do
        create_table :test_posts do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
      end
      Thread.report_on_exception, @original_report_on_exception = false, Thread.report_on_exception
    end

    before(:each) do
      set_logger
    end

    after(:each) do
      clear_logger
    end

    it "supports with_lock without raising ArgumentError (#2237)" do
      post = TestPost.create!(title: "lock me")
      expect {
        post.with_lock { post.update(title: "locked and updated") }
      }.not_to raise_error
      expect(post.reload.title).to eq("locked and updated")
    end

    it "Raises Deadlocked when a deadlock is encountered" do
      expect {
        barrier = Concurrent::CyclicBarrier.new(2)

        t1 = TestPost.create(title: "one")
        t2 = TestPost.create(title: "two")

        thread = Thread.new do
          TestPost.transaction do
            t1.lock!
            barrier.wait
            t2.update(title: "one")
          end
        end

        begin
          TestPost.transaction do
            t2.lock!
            barrier.wait
            t1.update(title: "two")
          end
        ensure
          thread.join
        end
      }.to raise_error(ActiveRecord::Deadlocked)
    end

    it "restarts the parent transaction on nested rollback without issuing a SAVEPOINT" do
      TestPost.transaction do
        TestPost.transaction(requires_new: true) do
          TestPost.create!(title: "inner")
          raise ActiveRecord::Rollback
        end
        TestPost.create!(title: "outer")
      end
      expect(TestPost.where(title: "inner").count).to eq 0
      expect(TestPost.where(title: "outer").count).to eq 1
      sql_log = @logger.logged(:debug)
      expect(sql_log.grep(/INSERT INTO.*TEST_POSTS/i)).not_to be_empty
      expect(sql_log.grep(/SAVEPOINT/i)).to be_empty
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost") rescue nil
      ActiveRecord::Base.clear_cache!
      Thread.report_on_exception = @original_report_on_exception
    end
  end

  describe "Sequence" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        create_table :table_with_name_thats_just_ok,
          sequence_name: "suitably_short_seq", force: true do |t|
          t.column :foo, :string, null: false
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :table_with_name_thats_just_ok,
          sequence_name: "suitably_short_seq" rescue nil
      end
    end

    it "should create table with custom sequence name" do
      expect(@conn.select_value("select suitably_short_seq.nextval from dual")).to eq(1)
    end
  end

  describe "Hints" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        drop_table :test_posts, if_exists: true
        create_table :test_posts
      end
      class ::TestPost < ActiveRecord::Base
      end
    end

    before(:each) do
      @conn.clear_cache!
      set_logger
    end

    after(:each) do
      clear_logger
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
      Object.send(:remove_const, "TestPost")
      ActiveRecord::Base.clear_cache!
    end

    it "should explain considers hints" do
      post = TestPost.optimizer_hints("FULL (\"TEST_POSTS\")")
      post = post.where(id: 1)
      expect(post.explain.inspect).to include("|  TABLE ACCESS FULL| TEST_POSTS |")
    end

    it "should explain considers hints with /*+ */" do
      post = TestPost.optimizer_hints("/*+ FULL (\"TEST_POSTS\") */")
      post = post.where(id: 1)
      expect(post.explain.inspect).to include("|  TABLE ACCESS FULL| TEST_POSTS |")
    end
  end

  describe "homogeneous in" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      @conn = ActiveRecord::Base.lease_connection
      schema_define do
        create_table :test_posts, force: true
        create_table :test_comments, force: true do |t|
          t.integer :test_post_id
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts, if_exists: true
        drop_table :test_comments, if_exists: true
      end
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      ActiveRecord::Base.clear_cache!
    end

    before(:each) do
      TestPost.delete_all
      TestComment.delete_all
    end

    it "should not raise undefined method length" do
      post = TestPost.create!
      post.test_comments << TestComment.create!
      expect(TestComment.where(test_post_id: TestPost.select(:id)).size).to eq(1)
    end

    it "should handle IN with subquery using Arel::Nodes::In" do
      post = TestPost.create!
      post.test_comments << TestComment.create!

      table = TestComment.arel_table
      subquery = TestPost.select(:id).arel
      in_node = Arel::Nodes::In.new(table[:test_post_id], subquery)
      query = table.where(in_node).project(Arel.star)

      sql = query.to_sql
      comments = TestComment.connection.select_all(sql).to_a
      expect(comments.size).to eq(1)

      # SQL should contain IN with subquery, not split into multiple IN clauses
      expect(sql).to match(/IN \(+SELECT/)
      expect(sql.scan(/IN \(/).size).to eq(1)
    end

    it "should handle NOT IN with subquery using Arel::Nodes::NotIn" do
      post = TestPost.create!
      TestComment.create!(test_post_id: post.id)
      orphan_comment = TestComment.create!(test_post_id: post.id + 1)

      table = TestComment.arel_table
      subquery = TestPost.select(:id).arel
      not_in_node = Arel::Nodes::NotIn.new(table[:test_post_id], subquery)
      query = table.where(not_in_node).project(Arel.star)

      sql = query.to_sql
      comments = TestComment.connection.select_all(sql).to_a

      expect(comments.size).to eq(1)
      expect(comments.first["id"]).to eq(orphan_comment.id)

      # SQL should contain NOT IN with subquery, not split into multiple NOT IN clauses
      expect(sql).to match(/NOT IN \(+SELECT/)
      expect(sql.scan(/NOT IN \(/).size).to eq(1)
    end
  end

  describe "data_source_exists? schema cache shortcut" do
    before(:all) do
      ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
      schema_define do
        create_table :test_data_source_exists, force: true do |t|
          t.string :title
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_data_source_exists, if_exists: true
      end
    end

    let(:conn) { ActiveRecord::Base.connection }
    let(:cache) { ActiveRecord::Base.connection_pool.schema_cache }

    def capture_dictionary_lookup
      events = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        events << payload
      end
      result = yield
      [result, events.select { |p| p[:name] == "SCHEMA" }]
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end

    it "fires no SCHEMA query when the table's columns are already in the schema cache" do
      cache.columns("test_data_source_exists")

      result, schema_queries = capture_dictionary_lookup { conn.data_source_exists?("test_data_source_exists") }
      expect(result).to be true
      expect(schema_queries).to be_empty
    end

    it "falls back to the live lookup for tables not in the schema cache" do
      cache.clear_data_source_cache!("test_data_source_exists")

      result, schema_queries = capture_dictionary_lookup { conn.data_source_exists?("test_data_source_exists") }
      expect(result).to be true
      expect(schema_queries).not_to be_empty
    end

    it "returns false for non-existing tables not in the cache" do
      expect(conn.data_source_exists?("test_nonexistent_xyz_table")).to be false
    end
  end
end
