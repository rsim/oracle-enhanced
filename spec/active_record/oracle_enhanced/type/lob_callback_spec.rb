# frozen_string_literal: true

# This spec demonstrates the critical difference between LOB handling with
# prepared statements (bind parameters) vs without (raw SQL with empty_clob()).
#
# BACKGROUND:
# - With prepared_statements: true, LOB data is bound as OCI8::CLOB/BLOB
#   temporary LOBs which are populated BEFORE the INSERT executes.
# - With prepared_statements: false, the SQL contains empty_clob()/empty_blob()
#   literals, and the LOB data MUST be written via a subsequent SELECT FOR UPDATE
#   + write operation (the write_lobs callback).
#
# IMPORTANT: The write_lobs callback in lob.rb is REQUIRED for the non-prepared
# case. Removing it will cause data loss when prepared_statements is disabled.
#
# See: https://github.com/rsim/oracle-enhanced/pull/2483 for context.

describe "OracleEnhancedAdapter LOB callbacks: prepared vs unprepared statements" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    schema_define do
      create_table :test_lob_callbacks, force: true do |t|
        t.string :name, limit: 50
        t.text   :clob_content
        t.binary :blob_content
      end
    end

    class ::TestLobCallback < ActiveRecord::Base
      self.table_name = "test_lob_callbacks"
    end
  end

  after(:all) do
    @conn.drop_table :test_lob_callbacks, if_exists: true
    Object.send(:remove_const, "TestLobCallback")
    ActiveRecord::Base.clear_cache!
  end

  after(:each) do
    TestLobCallback.delete_all
  end

  # Generate test data of specific sizes
  def clob_data(size_kb)
    "x" * (size_kb * 1024)
  end

  def blob_data(size_kb)
    Random.new(42).bytes(size_kb * 1024)
  end

  describe "with prepared_statements ENABLED (default)" do
    # This is the common case. LOB data flows through type_cast() which creates
    # OCI8::CLOB.new(connection, data) - a temporary LOB with data already in it.
    # Oracle copies this temp LOB into the table column during INSERT.

    it "creates record with small CLOB data" do
      record = TestLobCallback.create!(name: "small", clob_content: "Hello World")
      record.reload
      expect(record.clob_content).to eq("Hello World")
    end

    it "creates record with large CLOB data (100KB)" do
      data = clob_data(100)
      record = TestLobCallback.create!(name: "large_clob", clob_content: data)
      record.reload
      expect(record.clob_content).to eq(data)
      expect(record.clob_content.bytesize).to eq(100 * 1024)
    end

    it "creates record with very large CLOB data (1MB)" do
      data = clob_data(1024)
      record = TestLobCallback.create!(name: "very_large_clob", clob_content: data)
      record.reload
      expect(record.clob_content).to eq(data)
      expect(record.clob_content.bytesize).to eq(1024 * 1024)
    end

    it "creates record with BLOB data" do
      data = blob_data(10)
      record = TestLobCallback.create!(name: "blob", blob_content: data)
      record.reload
      expect(record.blob_content).to eq(data)
    end

    it "creates record with large BLOB data (512KB)" do
      data = blob_data(512)
      record = TestLobCallback.create!(name: "large_blob", blob_content: data)
      record.reload
      expect(record.blob_content).to eq(data)
      expect(record.blob_content.bytesize).to eq(512 * 1024)
    end

    it "updates record with CLOB data" do
      record = TestLobCallback.create!(name: "update_test")
      record.clob_content = clob_data(50)
      record.save!
      record.reload
      expect(record.clob_content.bytesize).to eq(50 * 1024)
    end
  end

  describe "with prepared_statements DISABLED" do
    # This is the critical case that requires the write_lobs callback.
    # Without bind parameters, the SQL contains empty_clob() literals.
    # The after_create/after_update callbacks MUST populate the LOB data.
    #
    # If you remove the lob.rb callbacks, these tests will FAIL:
    # - CLOB columns will be empty strings
    # - BLOB columns will be empty

    around(:each) do |example|
      old_prepared_statements = @conn.prepared_statements
      @conn.instance_variable_set(:@prepared_statements, false)
      begin
        example.run
      ensure
        @conn.instance_variable_set(:@prepared_statements, old_prepared_statements)
      end
    end

    context "CLOB creation (REQUIRES write_lobs callback)" do
      it "creates record with small CLOB data" do
        record = TestLobCallback.create!(name: "small_unprepared", clob_content: "Hello World")
        record.reload
        # WITHOUT write_lobs callback, this would be "" (empty string)
        expect(record.clob_content).to eq("Hello World")
      end

      it "creates record with medium CLOB data (10KB)" do
        data = clob_data(10)
        record = TestLobCallback.create!(name: "medium_clob_unprepared", clob_content: data)
        record.reload
        # WITHOUT write_lobs callback, this would be "" (empty string)
        expect(record.clob_content).to eq(data)
        expect(record.clob_content.bytesize).to eq(10 * 1024)
      end

      it "creates record with large CLOB data (100KB)" do
        data = clob_data(100)
        record = TestLobCallback.create!(name: "large_clob_unprepared", clob_content: data)
        record.reload
        # WITHOUT write_lobs callback, this would be "" (empty string)
        expect(record.clob_content).to eq(data)
        expect(record.clob_content.bytesize).to eq(100 * 1024)
      end

      it "creates record with very large CLOB data (1MB)" do
        data = clob_data(1024)
        record = TestLobCallback.create!(name: "very_large_clob_unprepared", clob_content: data)
        record.reload
        # WITHOUT write_lobs callback, this would be "" (empty string)
        expect(record.clob_content).to eq(data)
        expect(record.clob_content.bytesize).to eq(1024 * 1024)
      end

      it "creates record with empty CLOB" do
        record = TestLobCallback.create!(name: "empty_clob_unprepared", clob_content: "")
        record.reload
        expect(record.clob_content).to eq("")
      end
    end

    context "BLOB creation (REQUIRES write_lobs callback)" do
      it "creates record with small BLOB data" do
        data = blob_data(1)
        record = TestLobCallback.create!(name: "small_blob_unprepared", blob_content: data)
        record.reload
        # WITHOUT write_lobs callback, this would be empty/nil
        expect(record.blob_content).to eq(data)
      end

      it "creates record with large BLOB data (100KB)" do
        data = blob_data(100)
        record = TestLobCallback.create!(name: "large_blob_unprepared", blob_content: data)
        record.reload
        # WITHOUT write_lobs callback, this would be empty/nil
        expect(record.blob_content).to eq(data)
        expect(record.blob_content.bytesize).to eq(100 * 1024)
      end
    end

    context "CLOB updates (REQUIRES write_lobs callback)" do
      it "updates record with CLOB data from nil" do
        record = TestLobCallback.create!(name: "update_from_nil_unprepared")
        record.reload
        expect(record.clob_content).to be_nil

        record.clob_content = clob_data(50)
        record.save!
        record.reload
        # WITHOUT write_lobs callback, this would remain nil or be empty
        expect(record.clob_content.bytesize).to eq(50 * 1024)
      end

      it "updates record with CLOB data from existing data" do
        original_data = "original content"
        record = TestLobCallback.create!(name: "update_existing_unprepared", clob_content: original_data)
        record.reload
        expect(record.clob_content).to eq(original_data)

        new_data = clob_data(25)
        record.clob_content = new_data
        record.save!
        record.reload
        # WITHOUT write_lobs callback, this would still be the original data or empty
        expect(record.clob_content).to eq(new_data)
      end
    end
  end

  describe "SQL generation verification" do
    # These tests verify what SQL is generated in each mode,
    # demonstrating why the callback is necessary.

    it "uses bind parameters with prepared_statements enabled" do
      # When prepared_statements is true, LOB values go through type_cast()
      # which converts them to OCI8::CLOB objects (temp LOBs)
      expect(@conn.prepared_statements).to be true

      sql_log = []
      callback = ->(name, start, finish, id, payload) { sql_log << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        TestLobCallback.create!(name: "prepared_test", clob_content: "test data")
      end

      insert_sql = sql_log.find { |s| s.include?("INSERT") }
      # With prepared statements, SQL has bind placeholders, not literals
      expect(insert_sql).to include(":a1") # bind placeholder
      expect(insert_sql).not_to include("empty_clob()")
    end

    it "uses empty_clob() literal with prepared_statements disabled" do
      old_prepared_statements = @conn.prepared_statements
      @conn.instance_variable_set(:@prepared_statements, false)

      sql_log = []
      callback = ->(name, start, finish, id, payload) { sql_log << payload[:sql] }

      begin
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          TestLobCallback.create!(name: "unprepared_test", clob_content: "test data")
        end

        insert_sql = sql_log.find { |s| s.include?("INSERT") }
        # Without prepared statements, SQL has empty_clob() literal
        expect(insert_sql).to include("empty_clob()")

        # And there should be a SELECT FOR UPDATE to write the LOB data
        lob_write_sql = sql_log.find { |s| s.include?("FOR UPDATE") }
        expect(lob_write_sql).to be_present
      ensure
        @conn.instance_variable_set(:@prepared_statements, old_prepared_statements)
      end
    end
  end

  describe "edge cases and limitations" do
    around(:each) do |example|
      old_prepared_statements = @conn.prepared_statements
      @conn.instance_variable_set(:@prepared_statements, false)
      begin
        example.run
      ensure
        @conn.instance_variable_set(:@prepared_statements, old_prepared_statements)
      end
    end

    context "inline CLOB quoting limitations (for reference)" do
      # These tests document the limitations of inline LOB quoting approaches
      # like to_clob(varchar2_chunks). The write_lobs callback doesn't have
      # these limitations because it uses the LOB locator directly.

      it "handles CLOB content with special characters" do
        data = "Line 1\nLine 2\r\nLine 3\tTabbed\0NullByte"
        record = TestLobCallback.create!(name: "special_chars", clob_content: data)
        record.reload
        expect(record.clob_content).to eq(data)
      end

      it "handles CLOB content with unicode" do
        data = "Hello 世界 🌍 Ωmega"
        record = TestLobCallback.create!(name: "unicode", clob_content: data)
        record.reload
        expect(record.clob_content).to eq(data)
      end

      it "handles CLOB content with single quotes" do
        data = "It's a test with 'quoted' content and ''double quotes''"
        record = TestLobCallback.create!(name: "quotes", clob_content: data)
        record.reload
        expect(record.clob_content).to eq(data)
      end
    end
  end
end
