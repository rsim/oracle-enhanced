# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter schema definition" do
  include SchemaSpecHelper
  include LoggerSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  describe "option to create sequence when adding a column" do
    before do
      schema_define do
        create_table :keyboards, force: true, id: false do |t|
          t.string      :name
        end
        add_column :keyboards, :id, :primary_key
      end
      class ::Keyboard < ActiveRecord::Base; end
    end

    it "creates a sequence when adding a column with create_sequence = true" do
      _, sequence_name = ActiveRecord::Base.lease_connection.pk_and_sequence_for(:keyboards)

      expect(sequence_name).to eq(Keyboard.sequence_name)
    end
  end

  describe "table and sequence creation with non-default primary key" do
    before(:all) do
      schema_define do
        create_table :keyboards, force: true, id: false do |t|
          t.primary_key :key_number
          t.string      :name
        end
        create_table :id_keyboards, force: true do |t|
          t.string      :name
        end
      end
      class ::Keyboard < ActiveRecord::Base
        self.primary_key = :key_number
      end
      class ::IdKeyboard < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :keyboards
        drop_table :id_keyboards
      end
      Object.send(:remove_const, "Keyboard")
      Object.send(:remove_const, "IdKeyboard")
      ActiveRecord::Base.clear_cache!
    end

    it "should create sequence for non-default primary key" do
      expect(ActiveRecord::Base.lease_connection.next_sequence_value(Keyboard.sequence_name)).not_to be_nil
    end

    it "should create sequence for default primary key" do
      expect(ActiveRecord::Base.lease_connection.next_sequence_value(IdKeyboard.sequence_name)).not_to be_nil
    end
  end

  describe "primary_key inside create_table block with type and keyword options" do
    after(:each) do
      schema_define do
        drop_table :test_lookups, if_exists: true
      end
    end

    it "accepts a type argument and keyword options without raising ArgumentError" do
      expect {
        schema_define do
          create_table :test_lookups, force: true, id: false do |t|
            t.primary_key :zlookupid, :string, limit: 1, null: false
            t.string :name
          end
        end
      }.not_to raise_error

      columns = @conn.columns(:test_lookups)
      pk = columns.find { |c| c.name == "zlookupid" }
      expect(pk).not_to be_nil
      expect(pk.sql_type).to match(/VARCHAR2\(1\)/i)
      expect(pk.null).to be(false)
    end

    it "does not create a sequence for a non-numeric primary key" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :string, limit: 10, null: false
          t.string :name
        end
      end

      seq = @conn.select_value(<<~SQL.squish, "SCHEMA")
        SELECT 1 FROM user_sequences WHERE sequence_name = 'TEST_LOOKUPS_SEQ'
      SQL
      expect(seq).to be_nil
    end

    it "creates a sequence for an integer primary key" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :integer
          t.string :name
        end
      end

      seq = @conn.select_value(<<~SQL.squish, "SCHEMA")
        SELECT 1 FROM user_sequences WHERE sequence_name = 'TEST_LOOKUPS_SEQ'
      SQL
      expect(seq).not_to be_nil
    end

    it "creates a sequence for a bigint primary key" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :bigint
          t.string :name
        end
      end

      seq = @conn.select_value(<<~SQL.squish, "SCHEMA")
        SELECT 1 FROM user_sequences WHERE sequence_name = 'TEST_LOOKUPS_SEQ'
      SQL
      expect(seq).not_to be_nil
    end

    it "inserts via the Rails insert path on a String primary key" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :string, limit: 10, null: false
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_lookups"
        self.primary_key = "code"
      end

      expect { klass.create!(code: "ABC", name: "alpha") }.not_to raise_error
      expect(klass.find("ABC").name).to eq("alpha")
    end

    it "inserts via the Rails insert path on a String primary key when prepared_statements is false" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :string, limit: 10, null: false
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_lookups"
        self.primary_key = "code"
      end

      @conn.unprepared_statement do
        expect { klass.create!(code: "ABC", name: "alpha") }.not_to raise_error
        expect(klass.find("ABC").name).to eq("alpha")
      end
    end

    it "skips RETURNING when the caller supplies the String primary key value" do
      schema_define do
        create_table :test_lookups, force: true, id: false do |t|
          t.primary_key :code, :string, limit: 10, null: false
          t.string :name
        end
      end
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_lookups"
        self.primary_key = "code"
      end

      set_logger
      begin
        klass.create!(code: "ABC", name: "alpha")
        expect(@logger.output(:debug)).not_to match(/RETURNING/i)
      ensure
        clear_logger
      end
    end
  end

  describe "primary key with null: true" do
    # Regression coverage for the contract introduced in
    # rails/rails#57204: `add_column` must reject `null: true` on a
    # primary key. The actual ArgumentError is raised by the abstract
    # `new_column_definition` upstream; this spec guards against
    # oracle-enhanced's `new_column_definition` override (in
    # schema_definitions.rb) ever short-circuiting before the upstream
    # `super` call and silently letting the invalid combination
    # through.
    before(:all) do
      schema_define do
        create_table :test_pk_null_check, force: true do |t|
          t.string :name
        end
      end
    end

    after(:all) do
      schema_define { drop_table :test_pk_null_check, if_exists: true }
    end

    it "raises ArgumentError when adding a :primary_key column with null: true" do
      expect {
        @conn.add_column :test_pk_null_check, :other_id, :primary_key, null: true
      }.to raise_error(ArgumentError, /primary keys cannot be NULL/)
    end

    it "raises ArgumentError when adding a column with primary_key: true and null: true" do
      expect {
        @conn.add_column :test_pk_null_check, :another_id, :integer, primary_key: true, null: true
      }.to raise_error(ArgumentError, /primary keys cannot be NULL/)
    end
  end

  describe "default sequence name" do
    it "should return sequence name without truncating too much" do
      seq_name_length = ActiveRecord::Base.lease_connection.sequence_name_length
      tname = "#{DATABASE_USER}" + "." + "a" * (seq_name_length - DATABASE_USER.length) + "z" * (DATABASE_USER).length
      expect(ActiveRecord::Base.lease_connection.default_sequence_name(tname, nil)).to match (/z_seq$/)
    end

    it "truncates the trailing identifier by bytes for multibyte names" do
      conn = ActiveRecord::Base.lease_connection
      max = conn.sequence_name_length
      # "é" is 2 bytes in UTF-8. Build a name that exceeds the byte budget.
      name = "é" * max # 2 * max bytes, definitely over
      seq = conn.default_sequence_name(name, nil)
      expect(seq).to end_with("_seq")
      expect(seq.bytesize).to be <= max
    end

    it "preserves a schema prefix when truncating multibyte names" do
      conn = ActiveRecord::Base.lease_connection
      max = conn.sequence_name_length
      name = "schema." + ("é" * max)
      seq = conn.default_sequence_name(name, nil)
      expect(seq).to start_with("schema.")
      expect(seq).to end_with("_seq")
      table_part = seq.delete_prefix("schema.")
      expect(table_part.bytesize).to be <= max
    end

    it "backs off a byte when the naive byte slice would land mid-character" do
      conn = ActiveRecord::Base.lease_connection
      # Craft a name whose `max - 4` byte boundary lands in the middle of
      # a 2-byte character.
      max = conn.sequence_name_length
      ascii_prefix = "a" * (max - 4 - 1) # ends 1 byte short of budget
      name = ascii_prefix + "é" * 4      # é straddles the budget boundary
      seq = conn.default_sequence_name(name, nil)
      expect(seq).to end_with("_seq")
      expect(seq.bytesize).to be <= max
      expect(seq).to be_valid_encoding
    end
  end

  describe "sequence creation parameters" do
    def create_test_employees_table(sequence_start_value = nil)
      schema_define do
        options = sequence_start_value ? { sequence_start_value: sequence_start_value } : {}
        create_table :test_employees, **options do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end

    def save_default_sequence_start_value
      @saved_sequence_start_value = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value
    end

    def restore_default_sequence_start_value
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = @saved_sequence_start_value
    end

    before(:each) do
      save_default_sequence_start_value
    end

    after(:each) do
      restore_default_sequence_start_value
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should use default sequence start value 1" do
      expect(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value).to eq(1)

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      expect(employee.id).to eq(1)
    end

    it "should use specified default sequence start value" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 10000

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      expect(employee.id).to eq(10000)
    end

    it "should use sequence start value from table definition" do
      create_test_employees_table(10)
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      expect(employee.id).to eq(10)
    end

    it "should use sequence start value and other options from table definition" do
      create_test_employees_table("100 NOCACHE INCREMENT BY 10")
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      expect(employee.id).to eq(100)
      employee = TestEmployee.create!
      expect(employee.id).to eq(110)
    end
  end

  describe "table and column comments" do
    def create_test_employees_table(table_comment = nil, column_comments = {})
      schema_define do
        create_table :test_employees, comment: table_comment do |t|
          t.string      :first_name, comment: column_comments[:first_name]
          t.string      :last_name, comment: column_comments[:last_name]
        end
      end
    end

    before(:each) do
      @conn.clear_cache!
      set_logger
    end

    after(:each) do
      clear_logger
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.table_name_prefix = ""
      ActiveRecord::Base.clear_cache!
    end

    it "should create table with table comment" do
      table_comment = "Test Employees"
      create_test_employees_table(table_comment)
      class ::TestEmployee < ActiveRecord::Base; end
      expect(@conn.table_comment("test_employees")).to eq(table_comment)
    end

    it "should create table with columns comment" do
      column_comments = { first_name: "Given Name", last_name: "Surname" }
      create_test_employees_table(nil, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      [:first_name, :last_name].each do |attr|
        expect(@conn.column_comment("test_employees", attr.to_s)).to eq(column_comments[attr])
      end
      [:first_name, :last_name].each do |attr|
        expect(TestEmployee.columns_hash[attr.to_s].comment).to eq(column_comments[attr])
      end
    end

    it "should create table with table and columns comment and custom table name prefix" do
      ActiveRecord::Base.table_name_prefix = "xxx_"
      table_comment = "Test Employees"
      column_comments = { first_name: "Given Name", last_name: "Surname" }
      create_test_employees_table(table_comment, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      expect(@conn.table_comment(TestEmployee.table_name)).to eq(table_comment)
      [:first_name, :last_name].each do |attr|
        expect(@conn.column_comment(TestEmployee.table_name, attr.to_s)).to eq(column_comments[attr])
      end
      [:first_name, :last_name].each do |attr|
        expect(TestEmployee.columns_hash[attr.to_s].comment).to eq(column_comments[attr])
      end
    end

    it "should query table_comment using bind variables" do
      table_comment = "Test Employees"
      create_test_employees_table(table_comment)
      class ::TestEmployee < ActiveRecord::Base; end
      expect(@conn.table_comment(TestEmployee.table_name)).to eq(table_comment)
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_EMPLOYEES"\]\]/)
    end

    it "should query column_comment using bind variables" do
      table_comment = "Test Employees"
      column_comment = { first_name: "Given Name" }
      create_test_employees_table(table_comment, column_comment)
      class ::TestEmployee < ActiveRecord::Base; end
      expect(@conn.column_comment(TestEmployee.table_name, :first_name)).to eq(column_comment[:first_name])
      expect(@logger.logged(:debug).last).to match(/:table_name/)
      expect(@logger.logged(:debug).last).to match(/:column_name/)
      expect(@logger.logged(:debug).last).to match(/\["table_name", "TEST_EMPLOYEES"\], \["column_name", "FIRST_NAME"\]\]/)
    end
  end

  describe "drop tables" do
    after(:each) do
      schema_define do
        drop_table :multi_drop_posts, if_exists: true
        drop_table :multi_drop_comments, if_exists: true
      end
    end

    it "should drop table with :if_exists option no raise error" do
      expect do
        @conn.drop_table("nonexistent_table", if_exists: true)
      end.not_to raise_error
    end

    it "drops multiple tables in a single call" do
      schema_define do
        create_table :multi_drop_posts, force: true
        create_table :multi_drop_comments, force: true
      end

      expect do
        @conn.drop_table :multi_drop_posts, :multi_drop_comments
      end.not_to raise_error

      expect(@conn.table_exists?(:multi_drop_posts)).to be_falsey
      expect(@conn.table_exists?(:multi_drop_comments)).to be_falsey
    end
  end

  describe "rename tables and sequences" do
    before(:each) do
      schema_define do
        create_table  :test_employees, force: true do |t|
          t.string    :first_name
          t.string    :last_name
        end

        create_table  :test_employees_no_pkey, force: true, id: false do |t|
          t.string    :first_name
          t.string    :last_name
        end
      end
    end

    after(:each) do
      long_name = ("a" * (@conn.max_identifier_length - 3)).to_sym
      schema_define do
        drop_table :test_employees_no_primary_key, if_exists: true
        drop_table :test_employees, if_exists: true
        drop_table :new_test_employees, if_exists: true
        drop_table :test_employees_no_pkey, if_exists: true
        drop_table :new_test_employees_no_pkey, if_exists: true
        drop_table long_name, if_exists: true
      end
    end

    it "should rename table name with new one" do
      expect do
        @conn.rename_table("test_employees", "new_test_employees")
      end.not_to raise_error
    end

    it "should raise error when new table name length is too long" do
      expect do
        @conn.rename_table("test_employees", "a" * (@conn.max_identifier_length + 1))
      end.to raise_error(ArgumentError)
    end

    it "should not raise error when new sequence name length is too long" do
      expect do
        @conn.rename_table("test_employees", "a" * (@conn.max_identifier_length - 3))
      end.not_to raise_error
    end

    it "measures new table name length in bytes, not characters" do
      # "é" is 2 bytes in UTF-8, so half the max in chars is the full max
      # in bytes. The check fires on bytesize before any SQL is issued.
      multibyte_name = "é" * ((@conn.max_identifier_length / 2) + 1)
      expect(multibyte_name.bytesize).to be > @conn.max_identifier_length
      expect(multibyte_name.length).to be <= @conn.max_identifier_length
      expect do
        @conn.rename_table("test_employees", multibyte_name)
      end.to raise_error(ArgumentError)
    end

    it "should rename table when table has no primary key and sequence" do
      expect do
        @conn.rename_table("test_employees_no_pkey", "new_test_employees_no_pkey")
      end.not_to raise_error
    end

    it "renames the auto-generated sequence when the source table name is long enough to truncate it" do
      long_source = "a" * (@conn.max_identifier_length - 3)
      schema_define do
        create_table long_source.to_sym, force: true do |t|
          t.string :first_name
        end
      end

      expected_old_seq = @conn.default_sequence_name(long_source, nil).upcase
      expected_new_seq = @conn.default_sequence_name("new_test_employees", nil).upcase

      @conn.rename_table(long_source, "new_test_employees")

      sequences = @conn.select_values(
        "SELECT sequence_name FROM user_sequences WHERE sequence_name IN ('#{expected_old_seq}', '#{expected_new_seq}')"
      )
      expect(sequences).to include(expected_new_seq)
      expect(sequences).not_to include(expected_old_seq)
    end
  end

  describe "add index" do
    it "should return default index name if it is not larger than 30 characters" do
      expect(@conn.index_name("employees", column: "first_name")).to eq("index_employees_on_first_name")
    end

    it "should return shortened index name by removing 'index', 'on' and 'and' keywords" do
      if @conn.database_version >= "12.2"
        expect(@conn.index_name("employees", column: ["first_name", "email"])).to eq("index_employees_on_first_name_and_email")
      else
        expect(@conn.index_name("employees", column: ["first_name", "email"])).to eq("i_employees_first_name_email")
      end
    end

    it "should return shortened index name by shortening table and column names" do
      if @conn.database_version >= "12.2"
        expect(@conn.index_name("employees", column: ["first_name", "last_name"])).to eq("index_employees_on_first_name_and_last_name")
      else
        expect(@conn.index_name("employees", column: ["first_name", "last_name"])).to eq("i_emp_fir_nam_las_nam")
      end
    end

    it "should raise error if too large index name cannot be shortened" do
      if @conn.database_version >= "12.2"
        expect(@conn.index_name("test_employees", column: ["first_name", "middle_name", "last_name"])).to eq(
          ("index_test_employees_on_first_name_and_middle_name_and_last_name"))
      else
        expect(@conn.index_name("test_employees", column: ["first_name", "middle_name", "last_name"])).to eq(
          "i" + OpenSSL::Digest::SHA1.hexdigest("index_test_employees_on_first_name_and_middle_name_and_last_name")[0, 29]
        )
      end
    end

    it "supports expression indexes (function-based) via add_index" do
      schema_define do
        create_table :test_idx_expr, force: true do |t|
          t.string :name
        end
        add_index :test_idx_expr, "LOWER(name)", name: "ix_expr_lower_name"
      end
      idx_count = @conn.select_value(<<~SQL.squish)
        SELECT COUNT(*) FROM all_indexes
        WHERE
          owner = SYS_CONTEXT('userenv', 'current_schema')
          AND index_name = 'IX_EXPR_LOWER_NAME'
      SQL
      expect(idx_count).to eq(1)
      expr = @conn.select_value(<<~SQL.squish)
        SELECT column_expression FROM all_ind_expressions
        WHERE
          index_owner = SYS_CONTEXT('userenv', 'current_schema')
          AND index_name = 'IX_EXPR_LOWER_NAME'
      SQL
      expect(expr).to match(/LOWER\("?NAME"?\)/i)
    ensure
      schema_define { drop_table :test_idx_expr, if_exists: true }
    end

    it "reports supports_expression_index? as true" do
      expect(@conn.supports_expression_index?).to be(true)
    end

    it "supports per-column sort order in add_index" do
      schema_define do
        create_table :test_idx_sort, force: true do |t|
          t.string :first_name
          t.string :last_name
        end
        add_index :test_idx_sort, [:first_name, :last_name],
                  name: "ix_sort_order",
                  order: { first_name: :asc, last_name: :desc }
      end
      desc_count = @conn.select_value(<<~SQL.squish)
        SELECT COUNT(*) FROM all_ind_columns
        WHERE
          index_owner = SYS_CONTEXT('userenv', 'current_schema')
          AND index_name = 'IX_SORT_ORDER'
          AND descend = 'DESC'
      SQL
      expect(desc_count).to eq(1)
    ensure
      schema_define { drop_table :test_idx_sort, if_exists: true }
    end

    it "reports supports_index_sort_order? as true" do
      expect(@conn.supports_index_sort_order?).to be(true)
    end

    context "INVISIBLE indexes" do
      before(:each) do
        skip "Not supported in this database version" unless @conn.supports_disabling_indexes?
      end

      it "reports supports_disabling_indexes? as true" do
        expect(@conn.supports_disabling_indexes?).to be(true)
      end

      it "creates an INVISIBLE index when add_index passes enabled: false" do
        schema_define do
          create_table :test_idx_invisible, force: true do |t|
            t.string :name
          end
          add_index :test_idx_invisible, :name, name: "ix_idx_invisible", enabled: false
        end

        idx = @conn.indexes("test_idx_invisible").detect { |i| i.name == "ix_idx_invisible" }
        expect(idx).not_to be_nil
        expect(idx.disabled?).to be(true)
        expect(idx.enabled).to be(false)
      ensure
        schema_define { drop_table :test_idx_invisible, if_exists: true }
      end

      it "round-trips through disable_index / enable_index" do
        schema_define do
          create_table :test_idx_toggle, force: true do |t|
            t.string :name
          end
          add_index :test_idx_toggle, :name, name: "ix_idx_toggle"
        end

        idx_before = @conn.indexes("test_idx_toggle").detect { |i| i.name == "ix_idx_toggle" }
        expect(idx_before.enabled).to be(true)

        @conn.disable_index(:test_idx_toggle, "ix_idx_toggle")
        idx_after_disable = @conn.indexes("test_idx_toggle").detect { |i| i.name == "ix_idx_toggle" }
        expect(idx_after_disable.disabled?).to be(true)

        @conn.enable_index(:test_idx_toggle, "ix_idx_toggle")
        idx_after_enable = @conn.indexes("test_idx_toggle").detect { |i| i.name == "ix_idx_toggle" }
        expect(idx_after_enable.enabled).to be(true)
      ensure
        schema_define { drop_table :test_idx_toggle, if_exists: true }
      end

      # UNIQUE + INVISIBLE is a real combination: dual-write migrations and
      # "introduce uniqueness without changing query plans yet" workflows
      # both rely on adding a UNIQUE index in the disabled state.
      it "creates an INVISIBLE UNIQUE index when add_index passes unique: true, enabled: false" do
        schema_define do
          create_table :test_idx_unique_invisible, force: true do |t|
            t.string :name
          end
          add_index :test_idx_unique_invisible, :name, name: "ix_uniq_invisible", unique: true, enabled: false
        end

        idx = @conn.indexes("test_idx_unique_invisible").detect { |i| i.name == "ix_uniq_invisible" }
        expect(idx).not_to be_nil
        expect(idx.unique).to be(true)
        expect(idx.disabled?).to be(true)

        # Querying all_indexes directly confirms Oracle sees a UNIQUE INVISIBLE index.
        row = @conn.select_one(<<~SQL.squish)
          SELECT uniqueness, visibility FROM all_indexes
          WHERE
            owner = SYS_CONTEXT('userenv', 'current_schema')
            AND index_name = 'IX_UNIQ_INVISIBLE'
        SQL
        expect(row["uniqueness"]).to eq("UNIQUE")
        expect(row["visibility"]).to eq("INVISIBLE")
      ensure
        schema_define { drop_table :test_idx_unique_invisible, if_exists: true }
      end

      # The `change_table` block receiver (`OracleEnhanced::Table`) must
      # expose the same disable_index / enable_index API the connection
      # has, mirroring the MySQL adapter so migrations can write
      # `t.disable_index(:idx)` / `t.enable_index(:idx)` rather than
      # reaching back to the connection.
      it "exposes disable_index / enable_index on the change_table block receiver" do
        schema_define do
          create_table :test_idx_t_toggle, force: true do |t|
            t.string :name
          end
          add_index :test_idx_t_toggle, :name, name: "ix_t_toggle"
        end

        @conn.change_table :test_idx_t_toggle do |t|
          t.disable_index "ix_t_toggle"
        end
        idx = @conn.indexes("test_idx_t_toggle").detect { |i| i.name == "ix_t_toggle" }
        expect(idx.disabled?).to be(true)

        @conn.change_table :test_idx_t_toggle do |t|
          t.enable_index "ix_t_toggle"
        end
        idx = @conn.indexes("test_idx_t_toggle").detect { |i| i.name == "ix_t_toggle" }
        expect(idx.enabled).to be(true)
      ensure
        schema_define { drop_table :test_idx_t_toggle, if_exists: true }
      end
    end

    it "measures default index name length in bytes, not characters" do
      max = @conn.index_name_length
      # "index_t_on_<col>" fits in `max` characters but overflows in bytes
      # when <col> is multibyte. Without bytesize-awareness this would be
      # returned unchanged and Oracle would reject it.
      col = "é" * (max - "index_t_on_".length)
      default = "index_t_on_#{col}"
      expect(default.length).to eq(max)
      expect(default.bytesize).to be > max

      name = @conn.index_name("t", column: col)
      expect(name.bytesize).to be <= max
      expect(name).not_to eq(default)
    end
  end

  describe "rename index" do
  before(:each) do
    schema_define do
      create_table  :test_employees do |t|
        t.string    :first_name
        t.string    :last_name
      end
      add_index :test_employees, :first_name
    end
    class ::TestEmployee < ActiveRecord::Base; end
  end

  after(:each) do
    schema_define do
      drop_table :test_employees
    end
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.clear_cache!
  end

  it "should raise error when current index name and new index name are identical" do
    original_name = @conn.index_name("test_employees", column: "first_name")
    expect do
      @conn.rename_index("test_employees", original_name, original_name)
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "should raise error when new index name length is too long" do
    original_name = @conn.index_name("test_employees", column: "first_name")
    too_long = "a" * (@conn.max_identifier_length + 1)

    expect do
      @conn.rename_index("test_employees", original_name, too_long)
    end.to raise_error(ArgumentError)
  end

  it "should raise error when current index name does not exist" do
    expect do
      @conn.rename_index("test_employees", "nonexist_index_name", "new_index_name")
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "should rename index name with new one" do
    original_name = @conn.index_name("test_employees", column: "first_name")
    expect do
      @conn.rename_index("test_employees", original_name, "new_index_name")
    end.not_to raise_error
  end

  describe "bulk_change_table (Phase 1: add / change / remove column)" do
    before(:each) do
      schema_define do
        drop_table :test_bulk, if_exists: true
        create_table :test_bulk, force: true do |t|
          t.string :name
          t.integer :qty
          t.string :doomed
        end
      end
    end

    after(:each) do
      schema_define { drop_table :test_bulk, if_exists: true }
    end

    it "reports supports_bulk_alter? as true" do
      expect(@conn.supports_bulk_alter?).to be(true)
    end

    it "combines multiple add_column ops into a single ALTER TABLE ADD (...)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :added1
          t.integer :added2
          t.string :added3
        end
      end
      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      expect(add_alters.size).to eq(1)
      expect(add_alters.first).to match(/ADD \(.*ADDED1.*ADDED2.*ADDED3.*\)/im)

      cols = @conn.columns(:test_bulk).map(&:name)
      expect(cols).to include("added1", "added2", "added3")
    end

    it "combines add + change into ADD (...) MODIFY (...) in one ALTER" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :added_col
          t.change :qty, :decimal, precision: 10, scale: 2
        end
      end
      expect(sqls.size).to eq(1)
      # Lock in the exact clause shape: one ALTER TABLE that opens with
      # `ADD (...)` and is immediately followed by `MODIFY (...)` (no
      # trailing/leading clauses), so a regression that breaks the clauses
      # apart or reorders them shows up here rather than as a runtime ORA error.
      expect(sqls.first).to match(/\AALTER TABLE "?TEST_BULK"? ADD \(.+"?ADDED_COL"?.+\) MODIFY \(.+"?QTY"?.+\)\z/i)
    end

    it "preserves NOT NULL when bulk-changing a column" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change :qty, :integer, null: false
        end
      end
      expect(sqls.size).to eq(1)
      expect(sqls.first).to match(/MODIFY \(.*"?QTY"?.*NOT NULL.*\)/i)

      qty = @conn.columns(:test_bulk).detect { |c| c.name == "qty" }
      expect(qty.null).to be(false)
    end

    it "issues DROP COLUMN as a separate ALTER TABLE (Oracle ORA-12987)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :added_after_drop
          t.remove :doomed
        end
      end
      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      drop_alters = sqls.grep(/ALTER TABLE.*\bDROP\b/i)
      expect(add_alters.size).to eq(1)
      expect(drop_alters.size).to eq(1)
      # The two clauses must NOT appear together; that would raise ORA-12987.
      expect(sqls).to all(satisfy { |s| !(s.match?(/\bADD\b/i) && s.match?(/\bDROP\b/i)) })

      cols = @conn.columns(:test_bulk).map(&:name)
      expect(cols).to include("added_after_drop")
      expect(cols).not_to include("doomed")
    end

    it "applies all three operations on the live table" do
      @conn.change_table :test_bulk, bulk: true do |t|
        t.string :note
        t.change :qty, :decimal, precision: 8, scale: 2
        t.remove :doomed
      end

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols.keys).to include("note")
      expect(cols.keys).not_to include("doomed")
      expect(cols["qty"].sql_type).to match(/NUMBER\(8,\s*2\)/i)
    end

    # `t.remove :foo` followed by `t.string :foo` re-uses the same column
    # name. Oracle requires the DROP to land before the ADD or the second
    # ALTER fails because `foo` is still defined on the table.
    it "preserves migration order when remove precedes add of the same column" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.remove :doomed
          t.string :doomed, limit: 50
        end
      end

      expect(sqls.size).to eq(2)
      expect(sqls.first).to match(/\bDROP\b/i)
      expect(sqls.last).to match(/\bADD\b/i)

      doomed = @conn.columns(:test_bulk).detect { |c| c.name == "doomed" }
      expect(doomed).not_to be_nil
      expect(doomed.sql_type).to match(/VARCHAR2\(50\)/i)
    end

    it "issues an interleaved drop+add+drop block as three separate ALTERs in order" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.remove :doomed
          t.string :note
          t.remove :qty
        end
      end

      expect(sqls.size).to eq(3)
      expect(sqls[0]).to match(/\bDROP\b.*"?DOOMED"?/i)
      expect(sqls[1]).to match(/\bADD\b.*"?NOTE"?/i)
      expect(sqls[2]).to match(/\bDROP\b.*"?QTY"?/i)
    end

    # `comment:` requires a follow-up `COMMENT ON COLUMN` statement that
    # the column-only `add_column_for_alter` fragment does not include.
    # Falls back to `add_column` so the comment is applied.
    it "falls back to add_column when the column carries a comment" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql] }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :commented, comment: "audit"
        end
      end

      expect(sqls.any? { |s| s.match?(/COMMENT ON COLUMN.*COMMENTED/i) }).to be(true)
      expect(@conn.column_comment("test_bulk", "commented")).to eq("audit")
    end

    # `:primary_key` columns trigger sequence + trigger setup that the
    # column-only fragment does not reproduce; fall back to the full
    # `add_column` path which performs those statements.
    it "falls back to add_column for a :primary_key column type" do
      schema_define do
        drop_table :test_bulk_pk, if_exists: true
        create_table :test_bulk_pk, force: true, id: false do |t|
          t.string :name
        end
      end

      begin
        @conn.change_table :test_bulk_pk, bulk: true do |t|
          t.column :id, :primary_key
        end

        seq_exists = @conn.select_value(<<~SQL.squish) == 1
          SELECT COUNT(*) FROM all_sequences
          WHERE
            sequence_owner = SYS_CONTEXT('userenv', 'current_schema')
            AND sequence_name = 'TEST_BULK_PK_SEQ'
        SQL
        expect(seq_exists).to be(true)
      ensure
        schema_define { drop_table :test_bulk_pk, if_exists: true }
      end
    end

    it "raises NotImplementedError for ops outside Phase 1 scope (e.g. t.rename)" do
      expect {
        @conn.change_table :test_bulk, bulk: true do |t|
          t.rename :doomed, :renamed
        end
      }.to raise_error(NotImplementedError, /bulk_change_table.*:rename_column.*bulk: false/)
    end

    # Pre-scan guard: an unsupported op must raise BEFORE any ALTER fires,
    # otherwise an early `t.string` would commit and leave the schema in a
    # half-applied state when the rename later raised.
    it "rejects unsupported ops up front so no DDL is issued" do
      sqls = []
      expect {
        ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
          @conn.change_table :test_bulk, bulk: true do |t|
            t.string :added_first
            t.rename :doomed, :renamed
          end
        end
      }.to raise_error(NotImplementedError)

      cols = @conn.columns(:test_bulk).map(&:name)
      expect(cols).not_to include("added_first")
      expect(sqls).to be_empty
    end

    it "batches multiple t.remove calls into a single DROP (...) clause" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.remove :doomed
          t.remove :qty
        end
      end
      drops = sqls.grep(/ALTER TABLE.*\bDROP\b/i)
      expect(drops.size).to eq(1)
      expect(drops.first).to match(/DROP \(.*doomed.*qty.*\)/i)

      cols = @conn.columns(:test_bulk).map(&:name)
      expect(cols).not_to include("doomed", "qty")
    end

    it "flushes the queued ADD when a bulk block changes the column it just added" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :late_arrival
          t.change :late_arrival, :string, limit: 8, null: false
        end
      end
      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(add_alters.size).to eq(1)
      expect(modify_alters.size).to eq(1)

      col = @conn.columns(:test_bulk).find { |c| c.name == "late_arrival" }
      expect(col.sql_type).to match(/VARCHAR2\(8\)/i)
      expect(col.null).to be(false)
    end

    it "combines change_column_default and change_column_null into a single MODIFY clause" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_default :qty, 42
          t.change_null :name, false
        end
      end
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(modify_alters.size).to eq(1)
      expect(modify_alters.first).to match(/MODIFY \(.*qty.*DEFAULT.*42.*name.*NOT NULL.*\)/i)

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols["qty"].default.to_i).to eq(42)
      expect(cols["name"].null).to be(false)
    end

    it "combines add_column with change_column_default in a single ALTER" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :added_col
          t.change_default :qty, 7
        end
      end
      expect(sqls.size).to eq(1)
      expect(sqls.first).to match(/\AALTER TABLE.*ADD \(.*added_col.*\) MODIFY \(.*qty.*DEFAULT.*7.*\)\z/im)

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols).to include("added_col")
      expect(cols["qty"].default.to_i).to eq(7)
    end

    it "routes change_column_null through the full path when a default value is given (backfill UPDATE)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql] }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_null :qty, false, 0
        end
      end
      # The full change_column_null path issues UPDATE then MODIFY.
      expect(sqls.any? { |s| s.match?(/UPDATE.*test_bulk.*SET.*qty/i) }).to be(true)
      expect(sqls.any? { |s| s.match?(/ALTER TABLE.*MODIFY.*qty.*NOT NULL/i) }).to be(true)

      col = @conn.columns(:test_bulk).find { |c| c.name == "qty" }
      expect(col.null).to be(false)
    end

    it "flushes the queued ADD when bulk block sets default on a just-added column" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.integer :counter
          t.change_default :counter, 5
        end
      end
      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(add_alters.size).to eq(1)
      expect(modify_alters.size).to eq(1)

      col = @conn.columns(:test_bulk).find { |c| c.name == "counter" }
      expect(col.default.to_i).to eq(5)
    end

    it "flushes the queued ADD when bulk block sets NOT NULL on a just-added column" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :late_addition
          t.change_null :late_addition, false
        end
      end
      # `change_column_null_for_alter` calls `column_for`, which would not
      # see the just-added column unless the dispatcher flushed the ADD
      # first. Two ALTERs are expected: ADD then MODIFY NOT NULL.
      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(add_alters.size).to eq(1)
      expect(modify_alters.size).to eq(1)

      col = @conn.columns(:test_bulk).find { |c| c.name == "late_addition" }
      expect(col).not_to be_nil
      expect(col.null).to be(false)
    end

    it "skips a redundant change_null whose target matches the existing nullability" do
      sqls = []
      # `qty` is already nullable; asking for null: true is a no-op that
      # the non-bulk path silently skips. The bulk path must do the same
      # or Oracle raises ORA-01451 from MODIFY (col NULL).
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_null :qty, true
        end
      end
      expect(sqls).to be_empty
    end

    it "splits same-column change_default + change_null into separate ALTERs to avoid duplicate column in MODIFY" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_default :qty, 9
          t.change_null :qty, false
        end
      end
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(modify_alters.size).to eq(2)
      # Each ALTER must reference qty exactly once — never duplicate it
      # within a single MODIFY (..., ...) clause (ORA-00957 guard).
      modify_alters.each do |sql|
        expect(sql.scan(/"?QTY"?/i).size).to eq(1)
      end
      expect(modify_alters.first).to match(/DEFAULT.*9/i)
      expect(modify_alters.last).to match(/NOT NULL/i)

      col = @conn.columns(:test_bulk).find { |c| c.name == "qty" }
      expect(col.default.to_i).to eq(9)
      expect(col.null).to be(false)
    end

    it "splits duplicate change_default on the same column into separate ALTERs (last value wins on the table)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_default :qty, 1
          t.change_default :qty, 2
        end
      end
      modify_alters = sqls.grep(/ALTER TABLE.*\bMODIFY\b/i)
      expect(modify_alters.size).to eq(2)

      col = @conn.columns(:test_bulk).find { |c| c.name == "qty" }
      expect(col.default.to_i).to eq(2)
    end

    it "preserves user order across an interleaved change_default + add_column + change_null block" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.change_default :qty, 3
          t.string :extra
          t.change_null :name, false
        end
      end
      # Oracle 11g rejects `ALTER TABLE ADD (...) MODIFY (col1 ..., col2 ...)`
      # (ADD combined with multi-column MODIFY) with ORA-02264, even though
      # 12c+ accept it. The dispatcher therefore flushes the pending ADD +
      # first MODIFY before queuing the second MODIFY fragment, producing
      # two ALTERs in user-specified order.
      expect(sqls.size).to eq(2)
      expect(sqls[0]).to match(/ADD \(.*extra.*\) MODIFY \(.*qty.*DEFAULT.*3.*\)/i)
      expect(sqls[1]).to match(/MODIFY \(.*name.*NOT NULL.*\)/i)

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols).to include("extra")
      expect(cols["qty"].default.to_i).to eq(3)
      expect(cols["name"].null).to be(false)
    end

    it "clears a default by emitting MODIFY (col DEFAULT NULL)" do
      schema_define do
        drop_table :test_bulk_clear, if_exists: true
        create_table :test_bulk_clear, force: true do |t|
          t.integer :n, default: 7
        end
      end

      begin
        @conn.change_table :test_bulk_clear, bulk: true do |t|
          t.change_default :n, nil
        end

        col = @conn.columns(:test_bulk_clear).find { |c| c.name == "n" }
        expect(col.default).to be_nil
      ensure
        schema_define { drop_table :test_bulk_clear, if_exists: true }
      end
    end

    it "expands t.timestamps inside a bulk block into a single ALTER TABLE ADD (...)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.timestamps
        end
      end
      expect(sqls.size).to eq(1)
      expect(sqls.first).to match(/ADD \(.*created_at.*updated_at.*\)/i)
      expect(sqls.first).to match(/NOT NULL/i)

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols).to include("created_at", "updated_at")
      expect(cols["created_at"].null).to be(false)
      expect(cols["updated_at"].null).to be(false)
    end

    it "propagates t.timestamps options (null:, precision:) through the expansion" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.timestamps null: true, precision: 3
        end
      end
      expect(sqls.size).to eq(1)
      expect(sqls.first).to match(/TIMESTAMP\(3\)/i)
      expect(sqls.first).not_to match(/NOT NULL/i)

      cols = @conn.columns(:test_bulk).index_by(&:name)
      expect(cols["created_at"].null).to be(true)
      expect(cols["updated_at"].null).to be(true)
    end

    it "fuses t.timestamps with t.string into a single ADD (...)" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.string :note
          t.timestamps
        end
      end
      expect(sqls.size).to eq(1)
      expect(sqls.first).to match(/ADD \(.*note.*created_at.*updated_at.*\)/i)

      cols = @conn.columns(:test_bulk).map(&:name)
      expect(cols).to include("note", "created_at", "updated_at")
    end

    it "applies t.timestamps comment as separate COMMENT ON COLUMN after the bulk ADD" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql] }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.timestamps comment: "audit"
        end
      end

      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      comment_stmts = sqls.grep(/^COMMENT ON COLUMN/i)
      # `:comment` is stripped before expansion so the ADD stays combined;
      # the comment fires as separate COMMENT ON COLUMN statements (mirrors
      # the non-bulk `add_timestamps` flow added in #2739).
      expect(add_alters.size).to eq(1)
      expect(add_alters.first).to match(/ADD \(.*created_at.*updated_at.*\)/i)
      expect(comment_stmts.size).to eq(2)
      expect(@conn.column_comment("test_bulk", "created_at")).to eq("audit")
      expect(@conn.column_comment("test_bulk", "updated_at")).to eq("audit")
    end

    it "fires COMMENT ON COLUMN ... IS '' when t.timestamps comment: nil is passed in a bulk block" do
      sqls = []
      ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql] }, "sql.active_record") do
        @conn.change_table :test_bulk, bulk: true do |t|
          t.timestamps comment: nil
        end
      end

      add_alters = sqls.grep(/ALTER TABLE.*\bADD\b/i)
      comment_stmts = sqls.grep(/^COMMENT ON COLUMN/i)
      # `comment: nil` is the explicit-clear form that #2739's non-bulk
      # `add_timestamps` translates into `COMMENT ON COLUMN ... IS ''`.
      # The bulk path must keep the same parity — collect_timestamps_comments
      # must not silently drop the nil sentinel.
      expect(add_alters.size).to eq(1)
      expect(comment_stmts.size).to eq(2)
      expect(comment_stmts).to all(match(/IS\s+''/))
      expect(@conn.column_comment("test_bulk", "created_at")).to be_nil
      expect(@conn.column_comment("test_bulk", "updated_at")).to be_nil
    end

    it "expands t.remove_timestamps inside a bulk block into a single DROP (...)" do
      schema_define do
        drop_table :test_bulk_rm_ts, if_exists: true
        create_table :test_bulk_rm_ts, force: true do |t|
          t.string :name
          t.timestamps
        end
      end

      begin
        sqls = []
        ActiveSupport::Notifications.subscribed(->(_n, _s, _f, _id, payload) { sqls << payload[:sql] if payload[:sql]&.include?("ALTER TABLE") }, "sql.active_record") do
          @conn.change_table :test_bulk_rm_ts, bulk: true do |t|
            t.remove_timestamps
          end
        end
        drops = sqls.grep(/ALTER TABLE.*\bDROP\b/i)
        expect(drops.size).to eq(1)
        expect(drops.first).to match(/DROP \(.*updated_at.*created_at.*\)/i)

        cols = @conn.columns(:test_bulk_rm_ts).map(&:name)
        expect(cols).not_to include("created_at", "updated_at")
      ensure
        schema_define { drop_table :test_bulk_rm_ts, if_exists: true }
      end
    end
  end
end

  describe "remove index" do
    before(:each) do
      schema_define do
        create_table :test_employees do |t|
          t.string :first_name
          t.string :last_name
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees, if_exists: true
      end
      ActiveRecord::Base.clear_cache!
    end

    def capture_sql
      captured = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        captured << payload[:sql]
      end
      yield
      captured
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "drops a non-unique index without issuing a DROP CONSTRAINT" do
      schema_define do
        add_index :test_employees, :first_name, name: :idx_test_employees_first_name
      end

      sqls = capture_sql do
        schema_define do
          remove_index :test_employees, :first_name
        end
      end

      drop_constraint = sqls.find { |s| s =~ /DROP CONSTRAINT.*idx_test_employees_first_name/i }
      drop_index = sqls.find { |s| s =~ /DROP INDEX.*idx_test_employees_first_name/i }

      expect(drop_constraint).to be_nil
      expect(drop_index).not_to be_nil
      expect(@conn.index_exists?(:test_employees, :first_name)).to be(false)
    end

    it "drops a unique index together with its implicit constraint" do
      schema_define do
        add_index :test_employees, :first_name, unique: true, name: :uniq_test_employees_first_name
      end

      sqls = capture_sql do
        schema_define do
          remove_index :test_employees, :first_name
        end
      end

      drop_constraint = sqls.find { |s| s =~ /DROP CONSTRAINT.*uniq_test_employees_first_name/i }
      drop_index = sqls.find { |s| s =~ /DROP INDEX.*uniq_test_employees_first_name/i }

      expect(drop_constraint).not_to be_nil
      expect(drop_index).not_to be_nil
      expect(@conn.index_exists?(:test_employees, :first_name)).to be(false)
      expect(@conn.unique_constraints(:test_employees).map(&:name)).not_to include("uniq_test_employees_first_name")
    end

    it "honors if_exists: true when the index is missing" do
      sqls = capture_sql do
        schema_define do
          remove_index :test_employees, :first_name, if_exists: true
        end
      end

      expect(sqls.none? { |s| s =~ /DROP\s+(INDEX|CONSTRAINT)/i }).to be(true)
    end

    it "drops a unique functional index without issuing DROP CONSTRAINT" do
      schema_define do
        add_index :test_employees, "LOWER(first_name)", unique: true, name: :uniq_lower_first_name
      end

      sqls = capture_sql do
        schema_define do
          remove_index :test_employees, name: :uniq_lower_first_name
        end
      end

      drop_constraint = sqls.find { |s| s =~ /DROP CONSTRAINT.*uniq_lower_first_name/i }
      drop_index = sqls.find { |s| s =~ /DROP INDEX.*uniq_lower_first_name/i }

      expect(drop_constraint).to be_nil
      expect(drop_index).not_to be_nil
    end

    it "skips DROP CONSTRAINT after the implicit constraint was manually dropped" do
      schema_define do
        add_index :test_employees, :first_name, unique: true, name: :uniq_manual_drop
      end
      @conn.execute "ALTER TABLE test_employees DROP CONSTRAINT uniq_manual_drop"

      sqls = capture_sql do
        schema_define do
          remove_index :test_employees, name: :uniq_manual_drop
        end
      end

      drop_constraint = sqls.find { |s| s =~ /DROP CONSTRAINT/i }
      drop_index = sqls.find { |s| s =~ /DROP INDEX/i }

      expect(drop_constraint).to be_nil
      expect(drop_index).not_to be_nil
      expect(@conn.index_exists?(:test_employees, :first_name)).to be(false)
    end

    it "drops a unique index and its implicit constraint when name is given as a Symbol" do
      schema_define do
        add_index :test_employees, :first_name, unique: true, name: :uniq_sym_name
      end

      schema_define do
        remove_index :test_employees, name: :uniq_sym_name
      end

      expect(@conn.index_exists?(:test_employees, :first_name)).to be(false)
      expect(@conn.unique_constraints(:test_employees).map(&:name)).not_to include("uniq_sym_name")
    end

    it "raises ArgumentError when a divergent unique constraint references the index" do
      schema_define do
        add_index :test_employees, :first_name, name: :idx_divergent
        add_unique_constraint :test_employees, name: "uniq_divergent", using_index: :idx_divergent
      end

      expect {
        schema_define do
          remove_index :test_employees, name: :idx_divergent
        end
      }.to raise_error(ArgumentError, /idx_divergent.*used by unique constraint 'uniq_divergent'.*remove_unique_constraint/)

      # Ensure neither the index nor the constraint were touched.
      expect(@conn.index_exists?(:test_employees, :first_name)).to be(true)
      expect(@conn.unique_constraints(:test_employees).map(&:name)).to include("uniq_divergent")
    end

    it "succeeds when the divergent constraint is dropped before the index" do
      schema_define do
        add_index :test_employees, :first_name, name: :idx_divergent_ok
        add_unique_constraint :test_employees, name: "uniq_divergent_ok", using_index: :idx_divergent_ok
      end

      schema_define do
        remove_unique_constraint :test_employees, name: "uniq_divergent_ok"
        remove_index :test_employees, name: :idx_divergent_ok
      end

      expect(@conn.index_exists?(:test_employees, :first_name)).to be(false)
      expect(@conn.unique_constraints(:test_employees).map(&:name)).not_to include("uniq_divergent_ok")
    end
  end

  describe "add_index unique: true implicit constraint deprecation" do
    around(:each) do |example|
      original = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint
      example.run
    ensure
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = original
      schema_define do
        drop_table :test_dep_warn, if_exists: true
      end
    end

    before(:each) do
      schema_define do
        create_table :test_dep_warn, force: true do |t|
          t.string :first_name
          t.string :last_name
        end
      end
    end

    it "emits a deprecation warning and creates the implicit constraint by default" do
      expect {
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true
        @conn.add_index :test_dep_warn, :first_name, unique: true, name: :uniq_dep_default
      }.to output(/add_index :col, unique: true creates an implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_dep_warn).map(&:name)).to include("uniq_dep_default")
    end

    it "does not emit a warning and does not create the constraint when the flag is false" do
      expect {
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = false
        @conn.add_index :test_dep_warn, :first_name, unique: true, name: :uniq_dep_off
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_dep_warn).map(&:name)).not_to include("uniq_dep_off")
      expect(@conn.indexes(:test_dep_warn).map(&:name)).to include("uniq_dep_off")
    end

    it "skips both the warning and the constraint for functional unique indexes regardless of the flag" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true

      expect {
        @conn.add_index :test_dep_warn, "LOWER(first_name)", unique: true, name: :uniq_dep_func
      }.not_to output(/implicit named UNIQUE constraint/).to_stderr

      expect(@conn.unique_constraints(:test_dep_warn).map(&:name)).not_to include("uniq_dep_func")
    end

    it "emits the deprecation warning for inline t.index :col, unique: true inside create_table" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true
      begin
        # Bypass `schema_define` here — it wraps in `OracleEnhanced.deprecator.silence`,
        # which would suppress the very warning we want to capture.
        expect {
          ActiveRecord::Schema.define do
            suppress_messages do
              create_table :test_dep_inline, force: true do |t|
                t.string :first_name
                t.index :first_name, unique: true, name: :uniq_dep_inline
              end
            end
          end
        }.to output(/add_index :col, unique: true creates an implicit named UNIQUE constraint/).to_stderr

        expect(@conn.unique_constraints(:test_dep_inline).map(&:name)).to include("uniq_dep_inline")
      ensure
        schema_define { drop_table :test_dep_inline, if_exists: true }
      end
    end

    it "emits the deprecation warning for composite-column add_index unique: true" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true

      expect {
        @conn.add_index :test_dep_warn, [:first_name, :last_name], unique: true, name: :uniq_dep_composite
      }.to output(/add_index :col, unique: true creates an implicit named UNIQUE constraint/).to_stderr

      uc = @conn.unique_constraints(:test_dep_warn).detect { |u| u.name == "uniq_dep_composite" }
      expect(uc).not_to be_nil
    end

    it "includes a 'called from' frame in the deprecation warning so users can locate the call site" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = true

      # Lightweight call-site check: relies on ActiveSupport::Deprecation's
      # default `[:stderr]` behavior, which emits `(called from <caller>)`
      # appended to the message. If a future Rails release changes that
      # format, update the regex here rather than removing the assertion.
      expect {
        @conn.add_index :test_dep_warn, :first_name, unique: true, name: :uniq_dep_caller
      }.to output(/\(called from /).to_stderr
    end
  end

  describe "add_index with if_not_exists" do
    before(:each) do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
        add_index :test_posts, :title
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_posts, if_exists: true
      end
    end

    it "is a no-op when the index already exists" do
      expect do
        @conn.add_index :test_posts, :title, if_not_exists: true
      end.not_to raise_error
    end

    it "raises ArgumentError when the index already exists and if_not_exists is unset" do
      expect do
        @conn.add_index :test_posts, :title
      end.to raise_error(ArgumentError, /already exists/)
    end
  end

  describe "create_table with if_not_exists" do
    after(:each) do
      schema_define { drop_table :test_posts, if_exists: true }
    end

    it "creates the table when it does not yet exist" do
      schema_define do
        create_table :test_posts, if_not_exists: true do |t|
          t.string :title
        end
      end
      expect(@conn.data_source_exists?(:test_posts)).to be true
    end

    it "is a no-op when the table already exists" do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
      end

      expect do
        schema_define do
          create_table :test_posts, if_not_exists: true do |t|
            t.string :title
          end
        end
      end.not_to raise_error
    end

    it "raises ArgumentError when force and if_not_exists are combined" do
      expect do
        schema_define do
          create_table :test_posts, force: true, if_not_exists: true do |t|
            t.string :title
          end
        end
      end.to raise_error(ArgumentError, /cannot be used simultaneously/)
    end
  end

  describe "add timestamps" do
    before(:each) do
      schema_define do
        create_table :test_employees, force: true
      end
      class ::TestEmployee < ActiveRecord::Base; end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees, if_exists: true
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.clear_cache!
    end

    it "should add created_at and updated_at" do
      expect do
        @conn.add_timestamps("test_employees")
      end.not_to raise_error

      TestEmployee.reset_column_information
      expect(TestEmployee.columns_hash["created_at"]).not_to be_nil
      expect(TestEmployee.columns_hash["updated_at"]).not_to be_nil
    end

    it "applies :comment to created_at and updated_at" do
      @conn.add_timestamps("test_employees", comment: "audit")

      expect(@conn.column_comment("test_employees", "created_at")).to eq("audit")
      expect(@conn.column_comment("test_employees", "updated_at")).to eq("audit")
    end
  end

  describe "add_column / change_column comment handling" do
    before(:each) do
      schema_define do
        create_table :test_employees, force: true
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees, if_exists: true
      end
    end

    it "applies :comment to a newly added column" do
      @conn.add_column :test_employees, :note, :string, comment: "audit"

      expect(@conn.column_comment("test_employees", "note")).to eq("audit")
    end

    # Passing `comment: nil` is the canonical way to clear an existing
    # column comment (`change_column_comment_sql` emits
    # `COMMENT ON COLUMN ... IS ''` when the value is nil).
    it "clears the existing comment when add_column is called with comment: nil" do
      @conn.add_column :test_employees, :note, :string, comment: "audit"
      expect(@conn.column_comment("test_employees", "note")).to eq("audit")

      @conn.change_column :test_employees, :note, :string, comment: nil
      expect(@conn.column_comment("test_employees", "note")).to be_nil
    end
  end

  describe "ignore options for LOB columns" do
    after(:each) do
      schema_define do
        drop_table :test_posts
      end
    end

    it "should ignore :limit option for :text column" do
      expect do
        schema_define do
          create_table :test_posts, force: true do |t|
            t.text :body, limit: 10000
          end
        end
      end.not_to raise_error
    end

    it "should ignore :limit option for :binary column" do
      expect do
        schema_define do
          create_table :test_posts, force: true do |t|
            t.binary :picture, limit: 10000
          end
        end
      end.not_to raise_error
    end
  end

  describe "foreign key constraints" do
    let(:table_name_prefix) { "" }
    let(:table_name_suffix) { "" }

    before(:each) do
      ActiveRecord::Base.table_name_prefix = table_name_prefix
      ActiveRecord::Base.table_name_suffix = table_name_suffix
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post
          t.integer :post_id
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
      set_logger
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
      end
      ActiveRecord::Base.table_name_prefix = ""
      ActiveRecord::Base.table_name_suffix = ""
      ActiveRecord::Base.clear_cache!
      clear_logger
    end

    it "should add foreign key" do
      fk_name = "fk_rails_#{OpenSSL::Digest::SHA256.hexdigest("test_comments_test_post_id_fk").first(10)}"

      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291.*\.#{fk_name}/i) }
    end

    it "should add foreign key with name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "comments_posts_fk"
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291.*\.COMMENTS_POSTS_FK/) }
    end

    it "should add foreign key with column" do
      fk_name = "fk_rails_#{OpenSSL::Digest::SHA256.hexdigest("test_comments_post_id_fk").first(10)}"

      schema_define do
        add_foreign_key :test_comments, :test_posts, column: "post_id"
      end
      expect do
        TestComment.create(body: "test", post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291.*\.#{fk_name}/i) }
    end

    it "should add foreign key with delete dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, on_delete: :cascade
      end
      p = TestPost.create(title: "test")
      c = TestComment.create(body: "test", test_post: p)
      TestPost.delete(p.id)
      expect(TestComment.find_by_id(c.id)).to be_nil
    end

    it "should add foreign key with nullify dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, on_delete: :nullify
      end
      p = TestPost.create(title: "test")
      c = TestComment.create(body: "test", test_post: p)
      TestPost.delete(p.id)
      expect(TestComment.find_by_id(c.id).test_post_id).to be_nil
    end

    it "should remove foreign key by table name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, :test_posts
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.not_to raise_error
    end

    it "should remove foreign key by constraint name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "comments_posts_fk"
        remove_foreign_key :test_comments, name: "comments_posts_fk"
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.not_to raise_error
    end

    it "should remove foreign key by column name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, column: "test_post_id"
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.not_to raise_error
    end

    it "should query foreign_keys using bind variables" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      ActiveRecord::Base.lease_connection.foreign_keys(:test_comments)
      expect(@logger.logged(:debug).last).to match(/:desc_table_name/)
      expect(@logger.logged(:debug).last).to match(/\["desc_table_name", "TEST_COMMENTS"\]\]/)
    end

    it "should add deferrable initially deferred foreign key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, deferrable: :deferred
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:deferrable]).to eq(:deferred)
    end

    it "should add deferrable initially immediate foreign key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, deferrable: :immediate
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:deferrable]).to eq(:immediate)
    end

    it "should add non-deferrable foreign key when deferrable option is omitted" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:deferrable]).to be(false)
    end

    it "should raise ArgumentError when deferrable option is invalid" do
      expect {
        schema_define do
          add_foreign_key :test_comments, :test_posts, deferrable: true
        end
      }.to raise_error(ArgumentError, /deferrable must be `:immediate` or `:deferred`/)
    end

    it "creates a NOVALIDATE foreign key when validate: false is given" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, validate: false
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:validate]).to be(false)
    end

    it "validates a NOVALIDATE foreign key via validate_foreign_key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "fk_to_validate", validate: false
      end
      fk_before = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk_before.options[:validate]).to be(false)

      schema_define do
        validate_foreign_key :test_comments, :test_posts
      end
      fk_after = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk_after.options.key?(:validate)).to be(false)
    end

    it "supports change_table { |t| t.validate_foreign_key }" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "fk_ct_validate", validate: false
        change_table :test_comments do |t|
          t.validate_foreign_key :test_posts
        end
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options.key?(:validate)).to be(false)
    end

    it "validates a foreign key by name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "fk_by_name", validate: false
        validate_foreign_key :test_comments, name: "fk_by_name"
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options.key?(:validate)).to be(false)
    end

    it "validates a foreign key by column" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, column: :post_id, name: "fk_by_col", validate: false
        validate_foreign_key :test_comments, column: :post_id
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).detect { |f| f.options[:name] == "fk_by_col" }
      expect(fk).not_to be_nil
      expect(fk.options.key?(:validate)).to be(false)
    end

    it "creates DISABLE VALIDATE when enforced: false is given (validate defaults to true)" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options.key?(:validate)).to be(false)
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error(/ORA-25128/)
    end

    it "creates DISABLE NOVALIDATE when both enforced: false and validate: false are given (closest to PG NOT ENFORCED)" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false, validate: false
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.not_to raise_error
    end

    it "leaves both :enforced and :validate absent when the foreign key is ENABLE VALIDATE" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options.key?(:enforced)).to be(false)
      expect(fk.options.key?(:validate)).to be(false)
    end

    it "enables a DISABLEd foreign key via change_foreign_key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false, validate: false
        change_foreign_key :test_comments, :test_posts, enforced: true
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options.key?(:enforced)).to be(false)
      expect(fk.options.key?(:validate)).to be(false)
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error(/ORA-02291/)
    end

    it "disables an ENFORCED foreign key via change_foreign_key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        change_foreign_key :test_comments, :test_posts, enforced: false
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.not_to raise_error
    end

    it "raises ArgumentError when change_foreign_key is called without :enforced" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      expect do
        ActiveRecord::Base.lease_connection.change_foreign_key :test_comments, :test_posts
      end.to raise_error(ArgumentError, /change_foreign_key requires at least one option/)
    end

    it "toggles enforced via change_foreign_key identified by name:" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, name: "comments_posts_fk"
        change_foreign_key :test_comments, name: "comments_posts_fk", enforced: false
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
    end

    it "honors enforced: false on add_reference foreign_key option hash" do
      schema_define do
        drop_table :test_comments, if_exists: true
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
        end
        add_reference :test_comments, :test_post, foreign_key: { enforced: false, validate: false }
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
    end

    it "honors enforced: false on inline t.foreign_key inside create_table" do
      schema_define do
        drop_table :test_comments, if_exists: true
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post
          t.foreign_key :test_posts, enforced: false, validate: false
        end
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
    end

    it "round-trips enforced: false combined with deferrable: :deferred" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, enforced: false, validate: false, deferrable: :deferred
      end
      fk = ActiveRecord::Base.lease_connection.foreign_keys(:test_comments).first
      expect(fk.options[:enforced]).to be(false)
      expect(fk.options[:validate]).to be(false)
      expect(fk.options[:deferrable]).to eq(:deferred)
    end
  end

  describe "check constraints" do
    before(:each) do
      schema_define do
        create_table :test_products, force: true do |t|
          t.integer :price
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_products, if_exists: true
      end
      ActiveRecord::Base.clear_cache!
    end

    it "adds a check constraint with an explicit name" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "price_check"
      end
      ccs = @conn.check_constraints(:test_products)
      expect(ccs.size).to eq(1)
      expect(ccs.first.name).to eq("price_check")
      expect(ccs.first.expression).to match(/price\s*>\s*0/i)
    end

    it "auto-generates a name when none is supplied" do
      schema_define do
        add_check_constraint :test_products, "price > 0"
      end
      cc = @conn.check_constraints(:test_products).first
      expect(cc).not_to be_nil
      expect(cc.name).to match(/\Achk_rails_[0-9a-f]{10}\z/)
    end

    it "drains t.check_constraint declared inline in create_table" do
      schema_define do
        drop_table :test_products, if_exists: true
        create_table :test_products, force: true do |t|
          t.integer :price
          t.check_constraint "price > 100", name: "inline_check"
        end
      end
      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "inline_check" }
      expect(cc).not_to be_nil
    end

    it "removes a check constraint by name" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "rm_check"
        remove_check_constraint :test_products, name: "rm_check"
      end
      expect(@conn.check_constraints(:test_products).map(&:name)).not_to include("rm_check")
    end

    it "honors if_not_exists: true on add_check_constraint" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "ifne_check"
        add_check_constraint :test_products, "price > 0", name: "ifne_check", if_not_exists: true
      end
      expect(@conn.check_constraints(:test_products).map(&:name).count("ifne_check")).to eq(1)
    end

    it "honors if_exists: true on remove_check_constraint" do
      expect {
        schema_define do
          remove_check_constraint :test_products, name: "nonexistent_check", if_exists: true
        end
      }.not_to raise_error
    end

    it "raises ArgumentError on remove_check_constraint for a missing constraint without if_exists" do
      expect {
        schema_define do
          remove_check_constraint :test_products, name: "nonexistent_check"
        end
      }.to raise_error(ArgumentError, /no check constraint/)
    end

    it "supports a multi-column CHECK expression" do
      schema_define do
        drop_table :test_products, if_exists: true
        create_table :test_products, force: true do |t|
          t.integer :price
          t.integer :quantity
        end
        add_check_constraint :test_products, "price > 0 AND quantity >= 0", name: "multi_col_check"
      end
      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "multi_col_check" }
      expect(cc).not_to be_nil
      expect(cc.expression).to match(/price\s*>\s*0\s+and\s+quantity\s*>=\s*0/i)
    end

    it "creates a NOVALIDATE check constraint when validate: false is given" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "novalidate_check", validate: false
      end
      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "novalidate_check" }
      expect(cc).not_to be_nil
      expect(cc.validate?).to be(false)
    end

    it "drains inline t.check_constraint with validate: false" do
      schema_define do
        drop_table :test_products, if_exists: true
        create_table :test_products, force: true do |t|
          t.integer :price
          t.check_constraint "price > 0", name: "inline_novalidate", validate: false
        end
      end
      cc = @conn.check_constraints(:test_products).detect { |c| c.name == "inline_novalidate" }
      expect(cc).not_to be_nil
      expect(cc.validate?).to be(false)
    end

    it "validates a NOVALIDATE constraint via validate_check_constraint" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "to_validate", validate: false
      end
      expect(@conn.check_constraints(:test_products).detect { |c| c.name == "to_validate" }.validate?).to be(false)

      schema_define do
        validate_check_constraint :test_products, name: "to_validate"
      end
      expect(@conn.check_constraints(:test_products).detect { |c| c.name == "to_validate" }.validate?).to be(true)
    end

    it "validates a constraint by name via validate_constraint" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "to_validate2", validate: false
      end
      schema_define do
        validate_constraint :test_products, "to_validate2"
      end
      expect(@conn.check_constraints(:test_products).detect { |c| c.name == "to_validate2" }.validate?).to be(true)
    end

    it "supports change_table { |t| t.validate_check_constraint name: ... }" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "ct_validate_chk", validate: false
        change_table :test_products do |t|
          t.validate_check_constraint name: "ct_validate_chk"
        end
      end
      expect(@conn.check_constraints(:test_products).detect { |c| c.name == "ct_validate_chk" }.validate?).to be(true)
    end

    it "supports change_table { |t| t.validate_constraint(name) }" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "ct_validate_bare", validate: false
        change_table :test_products do |t|
          t.validate_constraint "ct_validate_bare"
        end
      end
      expect(@conn.check_constraints(:test_products).detect { |c| c.name == "ct_validate_bare" }.validate?).to be(true)
    end

    it "raises ActiveRecord::CheckViolation when a check constraint is violated (ORA-02290)" do
      schema_define do
        add_check_constraint :test_products, "price > 0", name: "violation_check"
      end
      expect do
        @conn.execute "INSERT INTO test_products (id, price) VALUES (1, -1)"
      end.to raise_error(ActiveRecord::CheckViolation, /ORA-02290/)
    end
  end

  describe "unique constraints" do
    before(:each) do
      schema_define do
        create_table :test_sections, force: true do |t|
          t.string :title
          t.integer :position
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_sections, if_exists: true
      end
      ActiveRecord::Base.clear_cache!
    end

    it "adds a unique constraint with an explicit name" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_position"
      end
      ucs = @conn.unique_constraints(:test_sections)
      expect(ucs.size).to eq(1)
      expect(ucs.first.name).to eq("uniq_position")
      expect(ucs.first.column).to eq(["position"])
    end

    it "auto-generates a constraint name when none is supplied" do
      schema_define do
        add_unique_constraint :test_sections, :position
      end
      ucs = @conn.unique_constraints(:test_sections)
      expect(ucs.size).to eq(1)
      expect(ucs.first.name).to match(/\Auniq_rails_[0-9a-f]{10}\z/)
    end

    it "allows attaching a unique constraint to an existing index via :using_index" do
      schema_define do
        add_index :test_sections, :position, unique: true, name: :idx_existing_unique
      end
      # The trailing constraint added by add_index already shares the index name; drop it
      # so we can re-attach a constraint with a different name pointing at the same index.
      @conn.execute "ALTER TABLE test_sections DROP CONSTRAINT idx_existing_unique"
      schema_define do
        add_unique_constraint :test_sections, name: "uniq_via_idx", using_index: :idx_existing_unique
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_via_idx" }
      expect(uc).not_to be_nil
      expect(uc.using_index).to eq("idx_existing_unique")
    end

    it "emits DEFERRABLE INITIALLY DEFERRED when :deferrable is :deferred" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_deferred", deferrable: :deferred
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_deferred" }
      expect(uc.deferrable).to eq(:deferred)
    end

    it "emits DEFERRABLE INITIALLY IMMEDIATE when :deferrable is :immediate" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_immediate", deferrable: :immediate
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_immediate" }
      expect(uc.deferrable).to eq(:immediate)
    end

    it "should add non-deferrable unique constraint when deferrable option is omitted" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_nondef"
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_nondef" }
      expect(uc.deferrable).to be(false)
    end

    it "supports deferrable + using_index together against a non-unique backing index" do
      schema_define do
        add_index :test_sections, :position, name: :idx_def_nonu
      end
      schema_define do
        add_unique_constraint :test_sections, name: "uniq_def_using", using_index: :idx_def_nonu, deferrable: :deferred
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_def_using" }
      expect(uc.deferrable).to eq(:deferred)
      expect(uc.using_index).to eq("idx_def_nonu")
    end

    it "raises ArgumentError on invalid :deferrable value" do
      expect {
        schema_define do
          add_unique_constraint :test_sections, :position, name: "uniq_bad", deferrable: true
        end
      }.to raise_error(ArgumentError, /deferrable must be `:immediate` or `:deferred`/)
    end

    it "raises ArgumentError when an expression column is supplied" do
      expect {
        schema_define do
          add_unique_constraint :test_sections, "LOWER(title)", name: "uniq_expr"
        end
      }.to raise_error(ArgumentError, /do not support expression columns/)
    end

    it "raises ArgumentError when a constraint with the same name already exists" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_dup"
      end
      expect {
        schema_define do
          add_unique_constraint :test_sections, :title, name: "uniq_dup"
        end
      }.to raise_error(ArgumentError, /already has a unique constraint named 'uniq_dup'/)
    end

    it "removes a unique constraint by name" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_rm_by_name"
        remove_unique_constraint :test_sections, name: "uniq_rm_by_name"
      end
      expect(@conn.unique_constraints(:test_sections).map(&:name)).not_to include("uniq_rm_by_name")
    end

    it "removes a unique constraint by column" do
      schema_define do
        add_unique_constraint :test_sections, :position, name: "uniq_rm_by_col"
        remove_unique_constraint :test_sections, :position
      end
      expect(@conn.unique_constraints(:test_sections).map(&:name)).not_to include("uniq_rm_by_col")
    end

    it "drains t.unique_constraint declared inline in create_table" do
      schema_define do
        drop_table :test_sections, if_exists: true
        create_table :test_sections, force: true do |t|
          t.string :title
          t.integer :position
          t.unique_constraint :position, name: "uniq_inline"
        end
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_inline" }
      expect(uc).not_to be_nil
      expect(uc.column).to eq(["position"])
    end

    it "supports t.unique_constraint inside change_table" do
      schema_define do
        change_table :test_sections do |t|
          t.unique_constraint :position, name: "uniq_change"
        end
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_change" }
      expect(uc).not_to be_nil
    end

    it "supports composite columns via add_unique_constraint" do
      schema_define do
        add_unique_constraint :test_sections, [:title, :position], name: "uniq_composite"
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_composite" }
      expect(uc).not_to be_nil
      expect(uc.column).to eq(["title", "position"])
    end

    it "supports composite columns via inline t.unique_constraint" do
      schema_define do
        drop_table :test_sections, if_exists: true
        create_table :test_sections, force: true do |t|
          t.string :title
          t.integer :position
          t.unique_constraint [:title, :position], name: "uniq_inline_composite"
        end
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_inline_composite" }
      expect(uc).not_to be_nil
      expect(uc.column).to eq(["title", "position"])
    end

    it "preserves divergent constraint and index names on round-trip" do
      schema_define do
        add_index :test_sections, :position, unique: true, name: :idx_div
      end
      @conn.execute "ALTER TABLE test_sections DROP CONSTRAINT idx_div"
      schema_define do
        add_unique_constraint :test_sections, name: "uniq_div", using_index: :idx_div
      end
      uc = @conn.unique_constraints(:test_sections).detect { |u| u.name == "uniq_div" }
      expect(uc.using_index).to eq("idx_div")
    end
  end

  describe "lob in table definition" do
    before do
      class ::TestPost < ActiveRecord::Base
      end
    end

    it "should use default tablespace for clobs" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = DATABASE_NON_DEFAULT_TABLESPACE
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:nclob] = nil
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = nil
      schema_define do
        create_table :test_posts, force: true do |t|
          t.text :test_clob
          t.ntext :test_nclob
          t.binary :test_blob
        end
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_CLOB'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_NCLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_BLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    it "should use default tablespace for nclobs" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:nclob] = DATABASE_NON_DEFAULT_TABLESPACE
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = nil
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = nil
      schema_define do
        create_table :test_posts, force: true do |t|
          t.text :test_clob
          t.ntext :test_nclob
          t.binary :test_blob
        end
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_NCLOB'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_CLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_BLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    it "should use default tablespace for blobs" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = DATABASE_NON_DEFAULT_TABLESPACE
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = nil
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:nclob] = nil
      schema_define do
        create_table :test_posts, force: true do |t|
          t.text :test_clob
          t.ntext :test_nclob
          t.binary :test_blob
        end
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_BLOB'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_CLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'TEST_NCLOB'")).not_to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    after do
      Object.send(:remove_const, "TestPost")
      schema_define do
        drop_table :test_posts, if_exists: true
      end
    end
  end

  describe "primary key in table definition" do
    before do
      class ::TestPost < ActiveRecord::Base
      end
    end

    it "should use default tablespace for primary key" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:index] = nil
      schema_define do
        create_table :test_posts, force: true
      end

      index_name = @conn.select_value(
        "SELECT index_name FROM all_constraints
            WHERE table_name = 'TEST_POSTS'
            AND constraint_type = 'P'
            AND owner = SYS_CONTEXT('userenv', 'current_schema')")

      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_indexes WHERE index_name = '#{index_name}'")).to eq("USERS")
    end

    it "should use non default tablespace for primary key" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:index] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        create_table :test_posts, force: true
      end

      index_name = @conn.select_value(
        "SELECT index_name FROM all_constraints
            WHERE table_name = 'TEST_POSTS'
            AND constraint_type = 'P'
            AND owner = SYS_CONTEXT('userenv', 'current_schema')")

      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_indexes WHERE index_name = '#{index_name}'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    after do
      Object.send(:remove_const, "TestPost")
      schema_define do
        drop_table :test_posts, if_exists: true
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:index] = nil
    end
  end

  describe "foreign key in table definition" do
    before(:each) do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
      end
      ActiveRecord::Base.clear_cache!
    end

    it "should add foreign key in create_table" do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post
          t.foreign_key :test_posts
        end
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291/) }
    end

    it "should add foreign key in create_table references" do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post, foreign_key: true
        end
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291/) }
    end

    it "should add foreign key in change_table" do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post
        end
        change_table :test_comments do |t|
          t.foreign_key :test_posts
        end
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291/) }
    end

    it "should add foreign key in change_table references" do
      schema_define do
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
        end
        change_table :test_comments do |t|
          t.references :test_post, foreign_key: true
        end
      end
      expect do
        TestComment.create(body: "test", test_post_id: 1)
      end.to raise_error() { |e| expect(e.message).to match(/ORA-02291/) }
    end
  end

  describe "disable referential integrity" do
    before(:each) do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
        create_table :test_comments, force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post, foreign_key: true
        end
        create_table "test_Mixed_Comments", force: true do |t|
          t.string :body, limit: 4000
          t.references :test_post, foreign_key: true
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table "test_Mixed_Comments", if_exists: true
        drop_table :test_comments, if_exists: true
        drop_table :test_posts, if_exists: true
      end
    end

    it "should disable all foreign keys" do
      expect do
        @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (1, 'test', 1)"
      end.to raise_error(ActiveRecord::InvalidForeignKey)
      @conn.disable_referential_integrity do
        expect do
          @conn.execute "INSERT INTO \"test_Mixed_Comments\" (id, body, test_post_id) VALUES (2, 'test', 2)"
          @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (2, 'test', 2)"
          @conn.execute "INSERT INTO test_posts (id, title) VALUES (2, 'test')"
        end.not_to raise_error
      end
      expect do
        @conn.execute "INSERT INTO test_comments (id, body, test_post_id) VALUES (3, 'test', 3)"
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "synonyms" do
    before(:all) do
      @username = CONNECTION_PARAMS[:username]
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title
        end
      end
    end

    after(:all) do
      schema_define do
        drop_table :test_posts
      end
    end

    before(:each) do
      class ::TestPost < ActiveRecord::Base
        self.table_name = "synonym_to_posts"
      end
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define do
        remove_synonym :synonym_to_posts
        remove_synonym :synonym_to_posts_seq
      end
      ActiveRecord::Base.clear_cache!
    end

    it "should create synonym to table and sequence" do
      schema_name = @username
      schema_define do
        add_synonym :synonym_to_posts, "#{schema_name}.test_posts", force: true
        add_synonym :synonym_to_posts_seq, "#{schema_name}.test_posts_seq", force: true
      end
      expect do
        TestPost.create(title: "test")
      end.not_to raise_error
    end
  end

  describe "prepared statement cache eviction on DDL" do
    before(:each) do
      skip "requires prepared_statements: true" unless @conn.prepared_statements
      schema_define do
        create_table :test_evict, force: true do |t|
          t.string :name
          t.integer :extra
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_evict, if_exists: true
      end
      ActiveRecord::Base.clear_cache!
    end

    def cached_prepared_sqls_for(table_name)
      pool = @conn.instance_variable_get(:@statements)
      return [] unless pool
      pool.map { |sql, _| sql }.select { |sql| sql.include?(@conn.send(:quote_table_name, table_name)) }
    end

    it "removes cached prepared statements after a column is dropped" do
      klass = Class.new(ActiveRecord::Base) { self.table_name = :test_evict }
      klass.create!(name: "before-ddl", extra: 1)
      expect(cached_prepared_sqls_for(:test_evict)).not_to be_empty

      schema_define do
        remove_column :test_evict, :extra
      end

      expect(cached_prepared_sqls_for(:test_evict)).to be_empty
    end

    it "removes cached prepared statements after the table is dropped" do
      klass = Class.new(ActiveRecord::Base) { self.table_name = :test_evict }
      klass.create!(name: "before-drop", extra: 1)
      expect(cached_prepared_sqls_for(:test_evict)).not_to be_empty

      schema_define do
        drop_table :test_evict, if_exists: true
      end

      expect(cached_prepared_sqls_for(:test_evict)).to be_empty
    end
  end

  describe "alter columns with column cache" do
    include LoggerSpecHelper

    before(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:clob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:nclob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:blob)
    end

    after(:all) do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:clob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:nclob)
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:blob)
    end

    before(:each) do
      schema_define do
        create_table :test_posts, force: true do |t|
          t.string :title, null: false
          t.string :content
        end
      end
      class ::TestPost < ActiveRecord::Base; end
      expect(TestPost.columns_hash["title"].null).to be_falsey
    end

    after(:each) do
      Object.send(:remove_const, "TestPost")
      schema_define { drop_table :test_posts }
      ActiveRecord::Base.clear_cache!
    end

    it "should change column to nullable" do
      schema_define do
        change_column :test_posts, :title, :string, null: true
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["title"].null).to be_truthy
    end

    it "should add column" do
      schema_define do
        add_column :test_posts, :body, :string
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["body"]).not_to be_nil
    end

    it "should add longer column" do
      skip unless @conn.database_version >= "12.2"
      schema_define do
        add_column :test_posts, "a" * 128, :string
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["a" * 128]).not_to be_nil
    end

    it "should add text type lob column with non_default tablespace" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:clob] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_column :test_posts, :body, :text
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'BODY'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    it "should add ntext type lob column with non_default tablespace" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:nclob] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_column :test_posts, :body, :ntext
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'BODY'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    it "should add blob column with non_default tablespace" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:blob] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_column :test_posts, :attachment, :binary
      end
      expect(TestPost.lease_connection.select_value("SELECT tablespace_name FROM user_lobs WHERE table_name='TEST_POSTS' and column_name = 'ATTACHMENT'")).to eq(DATABASE_NON_DEFAULT_TABLESPACE)
    end

    it "should rename column" do
      schema_define do
        rename_column :test_posts, :title, :subject
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["subject"]).not_to be_nil
      expect(TestPost.columns_hash["title"]).to be_nil
    end

    it "should remove column" do
      schema_define do
        remove_column :test_posts, :title
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["title"]).to be_nil
    end

    it "should remove column when using change_table" do
      schema_define do
        change_table :test_posts do |t|
          t.remove :title
        end
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["title"]).to be_nil
    end

    it "should remove multiple columns when using change_table" do
      schema_define do
        change_table :test_posts do |t|
          t.remove :title, :content
        end
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["title"]).to be_nil
      expect(TestPost.columns_hash["content"]).to be_nil
    end

    it "should ignore type and options parameter and remove column" do
      schema_define do
        remove_column :test_posts, :title, :string, if_exists: true
      end
      TestPost.reset_column_information
      expect(TestPost.columns_hash["title"]).to be_nil
    end
  end

  describe "virtual columns in create_table" do
    before(:each) do
      skip "Not supported in this database version" unless @conn.database_version >= "11"
    end

    it "should raise error if column expression is not provided" do
      expect {
        schema_define do
          create_table :test_fractions do |t|
            t.integer :field1
            t.virtual :field2
          end
        end
      }.to raise_error(RuntimeError, "No virtual column definition found.")
    end
  end

  describe "virtual columns" do
    before(:each) do
      skip "Not supported in this database version" unless @conn.database_version >= "11"
      expr = "( numerator/NULLIF(denominator,0) )*100"
      schema_define do
        create_table :test_fractions, force: true do |t|
          t.integer :numerator, default: 0
          t.integer :denominator, default: 0
          t.virtual :percent, as: expr
        end
      end
      class ::TestFraction < ActiveRecord::Base
        self.table_name = "test_fractions"
      end
      TestFraction.reset_column_information
    end

    after(:each) do
      if @conn.database_version >= "11"
        schema_define do
          drop_table :test_fractions
        end
      end
    end

    it "should include virtual columns and not try to update them" do
      tf = TestFraction.columns.detect { |c| c.virtual? }
      expect(tf).not_to be_nil
      expect(tf.name).to eq("percent")
      expect(tf.virtual?).to be true
      expect do
        tf = TestFraction.new(numerator: 20, denominator: 100)
        expect(tf.percent).to be_nil # not whatever is in DATA_DEFAULT column
        tf.save!
        tf.reload
      end.not_to raise_error
      expect(tf.percent.to_i).to eq(20)
    end

    it "should add virtual column" do
      schema_define do
        add_column :test_fractions, :rem, :virtual, as: "remainder(numerator, NULLIF(denominator,0))"
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == "rem" }
      expect(tf).not_to be_nil
      expect(tf.virtual?).to be true
      expect do
        tf = TestFraction.new(numerator: 7, denominator: 5)
        expect(tf.rem).to be_nil
        tf.save!
        tf.reload
      end.not_to raise_error
      expect(tf.rem.to_i).to eq(2)
    end

    it "should add virtual column with explicit type" do
      schema_define do
        add_column :test_fractions, :expression, :virtual, as: "TO_CHAR(numerator) || '/' || TO_CHAR(denominator)", type: :string, limit: 100
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == "expression" }
      expect(tf).not_to be_nil
      expect(tf.virtual?).to be true
      expect(tf.type).to be :string
      expect(tf.limit).to be 100
      expect do
        tf = TestFraction.new(numerator: 7, denominator: 5)
        expect(tf.expression).to be_nil
        tf.save!
        tf.reload
      end.not_to raise_error
      expect(tf.expression).to eq("7/5")
    end

    it "should change virtual column definition" do
      schema_define do
        change_column :test_fractions, :percent, :virtual,
          as: "ROUND((numerator/NULLIF(denominator,0))*100, 2)", type: :decimal, precision: 15, scale: 2
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == "percent" }
      expect(tf).not_to be_nil
      expect(tf.virtual?).to be true
      expect(tf.type).to be :decimal
      expect(tf.precision).to be 15
      expect(tf.scale).to be 2
      expect do
        tf = TestFraction.new(numerator: 11, denominator: 17)
        expect(tf.percent).to be_nil
        tf.save!
        tf.reload
      end.not_to raise_error
      expect(tf.percent).to eq("64.71".to_d)
    end

    it "should change virtual column type" do
      schema_define do
        change_column :test_fractions, :percent, :virtual, type: :decimal, precision: 12, scale: 5
      end
      TestFraction.reset_column_information
      tf = TestFraction.columns.detect { |c| c.name == "percent" }
      expect(tf).not_to be_nil
      expect(tf.virtual?).to be true
      expect(tf.type).to be :decimal
      expect(tf.precision).to be 12
      expect(tf.scale).to be 5
      expect do
        tf = TestFraction.new(numerator: 11, denominator: 17)
        expect(tf.percent).to be_nil
        tf.save!
        tf.reload
      end.not_to raise_error
      expect(tf.percent).to eq("64.70588".to_d)
    end
  end

  describe "materialized views" do
    before(:all) do
      schema_define do
        create_table  :test_employees, force: true do |t|
          t.string    :first_name
          t.string    :last_name
        end
      end
      @conn.execute("create materialized view sum_test_employees as select first_name, count(*) from test_employees group by first_name")
      class ::TestEmployee < ActiveRecord::Base; end
    end

    after(:all) do
      @conn.drop_if_exists("MATERIALIZED VIEW", "sum_test_employees")
      schema_define do
        drop_table :sum_test_employees, if_exists: true
        drop_table :test_employees, if_exists: true
      end
    end

    it "reports supports_materialized_views? as true" do
      expect(@conn.supports_materialized_views?).to be(true)
    end

    it "tables should not return materialized views" do
      expect(@conn.tables).not_to include("sum_test_employees")
    end

    it "materialized_views should return materialized views" do
      expect(@conn.materialized_views).to include("sum_test_employees")
    end
  end

  describe "miscellaneous options" do
    before(:all) do
      # `before(:each)` below stubs `execute` to capture DDL into a string
      # without running it. `Schema.define` (which `schema_define` wraps)
      # writes to `AR_INTERNAL_METADATA`, and the table's CREATE goes through
      # the stubbed `execute` — but the follow-up SELECT goes through
      # `perform_query`, which is not stubbed and raises ORA-00942 unless the
      # table already exists. Ensure it exists once here, before any test in
      # this block runs.
      ActiveRecord::Schema.define { }
    end

    before(:each) do
      @conn.instance_variable_set :@would_execute_sql, @would_execute_sql = +""
      class << @conn
        def execute(sql, name = nil); @would_execute_sql << sql << ";\n"; end
        def execute_batch(statements, name = nil, **kwargs)
          statements.each { |s| execute(s, name) }
        end
      end
    end

    after(:each) do
      class << @conn
        remove_method :execute
        remove_method :execute_batch
      end
      @conn.instance_eval { remove_instance_variable :@would_execute_sql }
    end

    it "should support the :options option to create_table" do
      schema_define do
        create_table :test_posts, options: "NOLOGGING", force: true do |t|
          t.string :title, null: false
        end
      end
      expect(@would_execute_sql).to match(/CREATE +TABLE .* \(.*\) NOLOGGING/)
    end

    it "should support the :tablespace option to create_table" do
      schema_define do
        create_table :test_posts, tablespace: "bogus", force: true do |t|
          t.string :title, null: false
        end
      end
      expect(@would_execute_sql).to match(/CREATE +TABLE .* \(.*\) TABLESPACE bogus/)
    end

    describe "creating a table with a tablespace defaults set" do
      after(:each) do
        @conn.drop_table :tablespace_tests, if_exists: true
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:table)
      end

      it "should use correct tablespace" do
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:table] = DATABASE_NON_DEFAULT_TABLESPACE
        @conn.create_table :tablespace_tests do |t|
          t.string :foo
        end
        expect(@would_execute_sql).to match(/CREATE +TABLE .* \(.*\) TABLESPACE #{DATABASE_NON_DEFAULT_TABLESPACE}/o)
      end
    end

    describe "creating an index-organized table" do
      after(:each) do
        @conn.drop_table :tablespace_tests, if_exists: true
        ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:table)
      end

      it "should use correct tablespace" do
        @conn.create_table :tablespace_tests, id: false, organization: "INDEX INITRANS 4 COMPRESS 1", tablespace: "bogus" do |t|
          t.integer :id
        end
        expect(@would_execute_sql).to match(/CREATE +TABLE .*\(.*\)\s+ORGANIZATION INDEX INITRANS 4 COMPRESS 1 TABLESPACE bogus/)
      end
    end

    it "should support the :options option to add_index" do
      schema_define do
        add_index :keyboards, :name, options: "NOLOGGING"
      end
      expect(@would_execute_sql).to match(/CREATE +INDEX .* ON .* \(.*\) NOLOGGING/)
    end

    it "should support the :tablespace option to add_index" do
      schema_define do
        add_index :keyboards, :name, tablespace: "bogus"
      end
      expect(@would_execute_sql).to match(/CREATE +INDEX .* ON .* \(.*\) TABLESPACE bogus/)
    end

    it "should use default_tablespaces in add_index" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces[:index] = DATABASE_NON_DEFAULT_TABLESPACE
      schema_define do
        add_index :keyboards, :name
      end
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces.delete(:index)
      expect(@would_execute_sql).to match(/CREATE +INDEX .* ON .* \(.*\) TABLESPACE #{DATABASE_NON_DEFAULT_TABLESPACE}/o)
    end

    it "should create unique function index but not create unique constraints" do
      schema_define do
        add_index :keyboards, "lower(name)", unique: true, name: :index_keyboards_on_lower_name
      end
      expect(@would_execute_sql).not_to include("ADD CONSTRAINT")
    end

    it "should add unique constraint only to the index where it was defined" do
      schema_define do
        add_index :keyboards, ["name"], unique: true, name: :this_index
      end
      # Match anywhere in the captured SQL rather than asserting on
      # `lines.last`. `schema_define` calls `ActiveRecord::Schema.define`,
      # which finishes by ensuring `schema_migrations` and
      # `internal_metadata` exist. Under :random order this describe can
      # run before any prior `Schema.define`, so the trailing `CREATE
      # TABLE "SCHEMA_MIGRATIONS"` (etc.) lands last in the captured SQL
      # and the assertion is unrelated to what the test is checking.
      expect(@would_execute_sql).to match(/ALTER +TABLE .* ADD CONSTRAINT .* UNIQUE \(.*\) USING INDEX "THIS_INDEX";/)
    end

    it "should emit CREATE UNIQUE INDEX and ADD CONSTRAINT for inline t.index unique: true" do
      schema_define do
        create_table :test_inline_index_posts, force: true do |t|
          t.string :title
          t.index :title, unique: true, name: :uniq_inline_title
        end
      end
      expect(@would_execute_sql).to match(/CREATE UNIQUE INDEX "UNIQ_INLINE_TITLE" ON "TEST_INLINE_INDEX_POSTS" \("TITLE"\)/)
      expect(@would_execute_sql).to match(/ALTER +TABLE "TEST_INLINE_INDEX_POSTS" ADD CONSTRAINT "UNIQ_INLINE_TITLE" UNIQUE \("TITLE"\) USING INDEX "UNIQ_INLINE_TITLE"/)
    end

    it "should emit CREATE UNIQUE INDEX without ADD CONSTRAINT for inline functional t.index unique: true" do
      schema_define do
        create_table :test_inline_index_posts, force: true do |t|
          t.string :title
          t.index "lower(title)", unique: true, name: :uniq_inline_lower_title
        end
      end
      expect(@would_execute_sql).to match(/CREATE UNIQUE INDEX "UNIQ_INLINE_LOWER_TITLE" ON "TEST_INLINE_INDEX_POSTS" \(lower\(title\)\)/)
      expect(@would_execute_sql).not_to include("ADD CONSTRAINT")
    end

    it "should emit CREATE INDEX without ADD CONSTRAINT for inline non-unique t.index" do
      schema_define do
        create_table :test_inline_index_posts, force: true do |t|
          t.string :title
          t.index :title, name: :idx_inline_title
        end
      end
      expect(@would_execute_sql).to match(/CREATE INDEX "IDX_INLINE_TITLE" ON "TEST_INLINE_INDEX_POSTS" \("TITLE"\)/)
      expect(@would_execute_sql).not_to include("ADD CONSTRAINT")
    end

    it "should emit TABLESPACE for inline t.index with :tablespace option" do
      schema_define do
        create_table :test_inline_index_posts, force: true do |t|
          t.string :title
          t.index :title, name: :idx_inline_title_ts, tablespace: "bogus"
        end
      end
      expect(@would_execute_sql).to match(/CREATE INDEX "IDX_INLINE_TITLE_TS" ON "TEST_INLINE_INDEX_POSTS" \("TITLE"\) TABLESPACE bogus/)
    end

    it "produces the same SQL whether unique index is defined inline or via explicit add_index" do
      schema_define do
        create_table :test_explicit_idx_posts, force: true do |t|
          t.string :title
        end
        add_index :test_explicit_idx_posts, :title, unique: true, name: :uniq_title
      end
      explicit_sql = @would_execute_sql.dup

      @would_execute_sql.replace("")
      schema_define do
        drop_table :test_explicit_idx_posts, if_exists: true
        create_table :test_explicit_idx_posts, force: true do |t|
          t.string :title
          t.index :title, unique: true, name: :uniq_title
        end
      end
      inline_sql = @would_execute_sql

      [/CREATE TABLE "TEST_EXPLICIT_IDX_POSTS"/, /CREATE UNIQUE INDEX "UNIQ_TITLE"/, /ALTER +TABLE "TEST_EXPLICIT_IDX_POSTS" ADD CONSTRAINT "UNIQ_TITLE" UNIQUE \("TITLE"\) USING INDEX "UNIQ_TITLE"/].each do |pattern|
        expect(explicit_sql).to match(pattern)
        expect(inline_sql).to match(pattern)
      end
    end
  end

  describe "load schema" do
    let(:versions) {
      %w(20160101000000 20160102000000 20160103000000)
    }

    before do
      ActiveRecord::Base.connection_pool.schema_migration.create_table
    end

    context "when INSERT ALL accepts 1000+ rows (Oracle 11.2 or later)" do
      it "should loads the migration schema table from insert versions sql" do
        skip "Not supported in this database version" unless ActiveRecord::Base.lease_connection.database_version >= "11.2"

        expect {
          @conn.execute @conn.send(:insert_versions_sql, versions)
        }.not_to raise_error

        expect(@conn.select_value("SELECT COUNT(version) FROM schema_migrations")).to eq versions.count
      end
    end

    context "when INSERT ALL is capped at 999 rows (Oracle older than 11.2)" do
      it "should loads the migration schema table from insert versions sql" do
        skip "Not supported in this database version" if ActiveRecord::Base.lease_connection.database_version >= "11.2"

        expect {
          versions.each { |version| @conn.execute @conn.send(:insert_versions_sql, version) }
        }.not_to raise_error

        expect(@conn.select_value("SELECT COUNT(version) FROM schema_migrations")).to eq versions.count
      end
    end

    after do
      ActiveRecord::Base.connection_pool.schema_migration.drop_table
    end
  end
end
