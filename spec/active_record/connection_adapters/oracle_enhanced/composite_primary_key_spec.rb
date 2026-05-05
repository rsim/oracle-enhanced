# frozen_string_literal: true

# Behavioural coverage for composite primary keys, ported from Rails'
# `activerecord/test/cases/primary_keys_test.rb` (CompositePrimaryKeyTest)
# plus a few `finder_test.rb` / `persistence_test.rb` cases so the Oracle
# adapter's introspection, RETURNING, and prefetch paths are exercised
# end-to-end against a real database.
#
# Association-level coverage (HABTM joins, `has_many :through`) lives in
# the sibling `composite_spec.rb` and is intentionally not duplicated here.

describe "OracleEnhancedAdapter composite primary key" do
  include SchemaSpecHelper
  include SchemaDumpingHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
  end

  before(:each) do
    schema_define do
      create_table :uber_barcodes, primary_key: ["region", "code"], force: true do |t|
        t.string  :region
        t.integer :code
      end
      create_table :barcodes_reverse, primary_key: ["code", "region"], force: true do |t|
        t.string  :region
        t.integer :code
      end
      create_table :travels, primary_key: ["from", "to"], force: true do |t|
        t.string :from
        t.string :to
      end
      create_table :cpk_books, primary_key: [:author_id, :id], force: true do |t|
        t.integer :author_id
        t.integer :id
        t.string  :title
        t.integer :revision
      end
      create_table :cpk_docs, primary_key: [:author_id, :id], force: true do |t|
        t.integer :author_id
        t.integer :id
        t.text    :body
        t.binary  :data
      end
    end

    stub_const("UberBarcode", Class.new(ActiveRecord::Base) { self.table_name = "uber_barcodes" })
    stub_const("CpkBook", Class.new(ActiveRecord::Base) { self.table_name = "cpk_books" })
    stub_const("CpkDoc", Class.new(ActiveRecord::Base) { self.table_name = "cpk_docs" })
  end

  after(:each) do
    schema_define do
      drop_table :uber_barcodes,    if_exists: true
      drop_table :barcodes_reverse, if_exists: true
      drop_table :travels,          if_exists: true
      drop_table :cpk_books,        if_exists: true
      drop_table :cpk_docs,         if_exists: true
    end
    @conn.schema_cache.clear!
  end

  describe "introspection" do
    it "primary_keys returns the declared column array" do
      expect(@conn.primary_keys("uber_barcodes")).to eq(["region", "code"])
    end

    it "primary_keys preserves declared column order (out-of-order CPK)" do
      expect(@conn.primary_keys("barcodes_reverse")).to eq(["code", "region"])
    end

    it "primary_keys handles reserved-word columns" do
      expect(@conn.primary_keys("travels")).to eq(["from", "to"])
    end

    it "primary_key returns the column array for a composite PK" do
      expect(@conn.primary_key("uber_barcodes")).to eq(["region", "code"])
    end

    it "primary_key returns a single String for a single-column PK" do
      schema_define do
        create_table :test_single_pks, force: true do |t|
          t.string :name
        end
      end
      expect(@conn.primary_key("test_single_pks")).to eq("id")
    ensure
      schema_define { drop_table :test_single_pks, if_exists: true }
    end

    it "primary_key returns nil for a table without a primary key" do
      schema_define do
        create_table :test_no_pks, id: false, force: true do |t|
          t.string :name
        end
      end
      expect(@conn.primary_key("test_no_pks")).to be_nil
    ensure
      schema_define { drop_table :test_no_pks, if_exists: true }
    end

    it "pk_and_sequence_for returns nil for a composite-PK table" do
      expect(@conn.pk_and_sequence_for("uber_barcodes")).to be_nil
    end

    it "pk_and_sequence_for emits no warning for a composite-PK table" do
      expect { @conn.pk_and_sequence_for("uber_barcodes") }.not_to output.to_stderr
    end
  end

  describe "model contract" do
    it "Model.primary_key returns the array for a CPK model" do
      expect(UberBarcode.primary_key).to eq(["region", "code"])
    end

    it "Model.composite_primary_key? is true for a CPK model" do
      expect(UberBarcode).to be_composite_primary_key
    end

    it "reconfiguring primary_key resets composite_primary_key?" do
      klass = Class.new(ActiveRecord::Base) { self.table_name = "cpk_books" }
      expect(klass).to be_composite_primary_key
      klass.primary_key = :id
      expect(klass).not_to be_composite_primary_key
    end

    it "to_key returns [nil, nil] for a new CPK record" do
      expect(CpkBook.new.to_key).to eq([nil, nil])
    end

    it "to_key returns the array after id= [a, b]" do
      book = CpkBook.new
      book.id = [1, 2]
      expect(book.to_key).to eq([1, 2])
    end

    it "id= assigns each PK column" do
      book = CpkBook.new
      book.id = [7, 9]
      expect(book.author_id).to eq(7)
      expect(book.read_attribute(:id)).to eq(9)
    end

    it "id= with a non-array value raises TypeError" do
      book = CpkBook.new
      expect { book.id = 1 }.to raise_error(TypeError)
    end

    it "id_was returns the previous tuple after id is changed on a persisted record" do
      book = CpkBook.create!(id: [1, 2], title: "X")
      book.id = [42, 42]
      expect(book.id_was).to eq([1, 2])
      expect(book.id).to eq([42, 42])
    end

    it "id? is false when any PK component is nil" do
      book = CpkBook.new(id: [1, 2])
      expect(book.id?).to be true
      [[42, nil], [nil, 42], [nil, nil]].each do |bad|
        book.id = bad
        expect(book.id?).to be false
      end
    end

    it "primary_key_values_present? reflects PK component completeness" do
      expect(CpkBook.new(id: [1, 1]).primary_key_values_present?).to be true
      expect(CpkBook.new.primary_key_values_present?).to be false
      expect(CpkBook.new(author_id: 1).primary_key_values_present?).to be false
      expect(CpkBook.new(id: [nil, 1]).primary_key_values_present?).to be false
    end
  end

  describe "schema dump" do
    it "round-trips composite primary keys" do
      schema = dump_table_schema("uber_barcodes")
      expect(schema).to match(/create_table "uber_barcodes", primary_key: \["region", "code"\]/)
    end

    it "preserves declared column order for out-of-order composite primary keys" do
      schema = dump_table_schema("barcodes_reverse")
      expect(schema).to match(/create_table "barcodes_reverse", primary_key: \["code", "region"\]/)
    end
  end

  describe "prefetch / RETURNING" do
    it "prefetch_primary_key? returns false for a composite-PK table" do
      expect(@conn.prefetch_primary_key?("uber_barcodes")).to be false
    end

    it "prefetch_primary_key? remains true for a single-column PK table" do
      schema_define do
        create_table :test_single_pks, force: true do |t|
          t.string :name
        end
      end
      expect(@conn.prefetch_primary_key?("test_single_pks")).to be true
    ensure
      schema_define { drop_table :test_single_pks, if_exists: true }
    end

    # Regression for the dictionary fallback: when the schema cache is cold,
    # `prefetch_primary_key_from_dictionary` must still return true for a
    # single-column PK and false for a composite PK. (A buggy
    # `composite_primary_key?(pks)` Array-check incorrectly short-circuited
    # every PK table to false because `primary_keys` always returns an Array.)
    it "prefetch_primary_key? hits the dictionary path correctly with a cold schema cache" do
      schema_define do
        create_table :test_single_pks, force: true do |t|
          t.string :name
        end
      end
      @conn.instance_variable_get(:@prefetch_primary_key_cache).delete("test_single_pks")
      @conn.schema_cache.clear_data_source_cache!("test_single_pks")
      expect(@conn.prefetch_primary_key?("test_single_pks")).to be true

      @conn.instance_variable_get(:@prefetch_primary_key_cache).delete("uber_barcodes")
      @conn.schema_cache.clear_data_source_cache!("uber_barcodes")
      expect(@conn.prefetch_primary_key?("uber_barcodes")).to be false
    ensure
      schema_define { drop_table :test_single_pks, if_exists: true }
    end

    it "create! persists a CPK record with explicit id and returns the array via id" do
      book = CpkBook.create!(id: [1, 2], title: "First")
      expect(book.id).to eq([1, 2])
      reloaded = CpkBook.find([1, 2])
      expect(reloaded.title).to eq("First")
    end

    it "create! survives an INSERT that triggers the multi-column RETURNING path" do
      record = UberBarcode.create!(region: "JP", code: 100)
      expect(record.id).to eq(["JP", 100])
    end

    # Regression test for an empty-INSERT path on a composite-PK table whose
    # columns have literal defaults: AR emits
    #   INSERT INTO ... ("A", "B") VALUES (DEFAULT, DEFAULT)
    # and the adapter must append a multi-column RETURNING for both PK columns
    # so AR can read the database-generated values back into `id`.
    it "emits multi-column RETURNING for an empty INSERT on a CPK table with column defaults" do
      schema_define do
        create_table :test_cpk_defaults, primary_key: [:a, :b], force: true do |t|
          t.integer :a, default: 7
          t.integer :b, default: 9
        end
      end
      stub_const("CpkDefault", Class.new(ActiveRecord::Base) { self.table_name = "test_cpk_defaults" })

      record = CpkDefault.create!
      expect(record.id).to eq([7, 9])
      expect(CpkDefault.find([7, 9])).to eq(record)
    ensure
      schema_define { drop_table :test_cpk_defaults, if_exists: true }
    end
  end

  describe "schema cache" do
    it "caches the composite primary key column array" do
      cache = @conn.schema_cache
      cache.clear_data_source_cache!("uber_barcodes")

      first  = cache.primary_keys("uber_barcodes")
      second = cache.primary_keys("uber_barcodes")

      expect(first).to eq(["region", "code"])
      expect(second).to eq(["region", "code"])
      expect(second.equal?(first)).to be true
    end

    it "clear_data_source_cache! invalidates the cached composite PK" do
      cache = @conn.schema_cache
      expect(cache.primary_keys("uber_barcodes")).to eq(["region", "code"])

      cache.clear_data_source_cache!("uber_barcodes")
      schema_define do
        drop_table :uber_barcodes
        create_table :uber_barcodes, primary_key: ["code", "region"], force: true do |t|
          t.string  :region
          t.integer :code
        end
      end

      expect(cache.primary_keys("uber_barcodes")).to eq(["code", "region"])
    end
  end

  describe "find / update / destroy" do
    before do
      @first  = CpkBook.create!(id: [1, 10], title: "Alpha", revision: 1)
      @second = CpkBook.create!(id: [1, 20], title: "Bravo", revision: 1)
    end

    it "find returns the matching CPK record" do
      expect(CpkBook.find([1, 10])).to eq(@first)
    end

    it "find with a single composite key wrapped in an array returns one record in an array" do
      expect(CpkBook.find([[1, 10]])).to eq([@first])
    end

    it "find raises RecordNotFound for an unknown composite key" do
      expect { CpkBook.find([1, 999]) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "find with multiple composite keys preserves the requested order" do
      expect(CpkBook.find([1, 20], [1, 10])).to eq([@second, @first])
    end

    it "updates a non-PK column on a CPK record" do
      @first.update!(title: "Renamed")
      expect(CpkBook.find([1, 10]).title).to eq("Renamed")
    end

    it "destroy removes only the matching CPK row" do
      @first.destroy
      expect(CpkBook.where(author_id: 1).pluck(:id)).to eq([20])
    end

    it "class-level destroy with multiple composite keys deletes all matching rows" do
      CpkBook.destroy([[1, 10], [1, 20]])
      expect(CpkBook.where(author_id: 1)).to be_empty
    end

    it "predicate-builder lookup by individual PK columns finds the record" do
      expect(CpkBook.where(author_id: 1, id: 10).first).to eq(@first)
    end
  end

  describe "mixed-type composite primary key (String + Integer)" do
    before do
      @jp100 = UberBarcode.create!(region: "JP", code: 100)
      @us200 = UberBarcode.create!(region: "US", code: 200)
    end

    it "round-trips both component types via id" do
      expect(@jp100.id).to eq(["JP", 100])
      expect(UberBarcode.find(["JP", 100])).to eq(@jp100)
    end

    it "find with multiple mixed-type composite keys preserves order" do
      expect(UberBarcode.find(["US", 200], ["JP", 100])).to eq([@us200, @jp100])
    end

    it "destroy removes only the matching mixed-type row" do
      @jp100.destroy
      expect(UberBarcode.pluck(:region, :code)).to eq([["US", 200]])
    end
  end

  describe "CLOB / BLOB columns" do
    it "create! persists a CLOB body above the inline VARCHAR2 limit" do
      body = "x" * 5000
      CpkDoc.create!(id: [1, 1], body: body)
      expect(CpkDoc.find([1, 1]).body).to eq(body)
    end

    describe "with prepared_statements disabled" do
      around(:each) do |example|
        old_prepared_statements = @conn.prepared_statements
        @conn.instance_variable_set(:@prepared_statements, false)
        example.run
        @conn.instance_variable_set(:@prepared_statements, old_prepared_statements)
      end

      it "create! writes a CLOB body via write_lobs when prepared_statements is false" do
        body = "x" * 5000
        CpkDoc.create!(id: [2, 2], body: body)
        expect(CpkDoc.find([2, 2]).body).to eq(body)
      end

      it "create! writes a BLOB data column via write_lobs when prepared_statements is false" do
        data = ("\x00\x01\x02\x03".b * 1500)
        CpkDoc.create!(id: [3, 3], data: data)
        expect(CpkDoc.find([3, 3]).data).to eq(data)
      end
    end

    it "insert_fixture writes a CLOB body for a CPK model" do
      body = "y" * 5000
      @conn.insert_fixture({ "author_id" => 7, "id" => 9, "body" => body }, "cpk_docs")
      expect(CpkDoc.find([7, 9]).body).to eq(body)
    end
  end
end
