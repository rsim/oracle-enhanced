# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_oracle_common_lobs, force: true do |t|
        t.text   :body
        t.binary :payload
        t.string :name
      end
    end
    # Warm the schema cache so `cached_column_for` (which uses cached
    # lookups only) can resolve attribute types in the assertions below.
    ActiveRecord::Base.connection.schema_cache.columns_hash("test_oracle_common_lobs")
  end

  after(:all) do
    schema_define do
      drop_table :test_oracle_common_lobs, if_exists: true
    end
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(name: :test_oracle_common_lobs)
  end

  def compile(node)
    @visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  describe "visit_Arel_Nodes_Equality" do
    it "rewrites equality on a :text column to DBMS_LOB.COMPARE = 0" do
      node = Arel::Nodes::Equality.new(@table[:body], Arel::Nodes::Casted.new("hello", @table[:body]))
      expect(compile(node)).to match(/DBMS_LOB\.COMPARE\(.*"BODY".*'hello'.*\)\s*=\s*0/)
    end

    it "rewrites equality on a :binary column to DBMS_LOB.COMPARE = 0" do
      node = Arel::Nodes::Equality.new(@table[:payload], Arel::Nodes::Casted.new("x", @table[:payload]))
      expect(compile(node)).to match(/DBMS_LOB\.COMPARE\(.*"PAYLOAD".*\)\s*=\s*0/)
    end

    it "leaves equality on a :string column as plain `=`" do
      node = Arel::Nodes::Equality.new(@table[:name], Arel::Nodes::Casted.new("foo", @table[:name]))
      sql = compile(node)
      expect(sql).not_to match(/DBMS_LOB/)
      expect(sql).to match(/"NAME"\s*=\s*'foo'/)
    end

    it "falls through to plain `=` when the table is not in the schema cache" do
      unknown_table = Arel::Table.new(name: :test_oracle_common_no_such_table)
      node = Arel::Nodes::Equality.new(unknown_table[:any], Arel::Nodes::Casted.new("x", unknown_table[:any]))
      expect(compile(node)).not_to match(/DBMS_LOB/)
    end

    it "falls through to plain `=` when the left side is not an Arel::Attributes::Attribute" do
      literal = Arel::Nodes::SqlLiteral.new("dummy_fn()")
      node = Arel::Nodes::Equality.new(literal, Arel.sql("'x'"))
      expect(compile(node)).not_to match(/DBMS_LOB/)
    end

    it "does not rewrite NotEqual on a :text column" do
      node = Arel::Nodes::NotEqual.new(@table[:body], Arel::Nodes::Casted.new("hello", @table[:body]))
      expect(compile(node)).not_to match(/DBMS_LOB/)
    end

    it "does not rewrite GreaterThan on a :text column" do
      node = Arel::Nodes::GreaterThan.new(@table[:body], Arel::Nodes::Casted.new("hello", @table[:body]))
      expect(compile(node)).not_to match(/DBMS_LOB/)
    end

    it "rewrites equality the same way via Arel::Visitors::Oracle" do
      oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
      node = Arel::Nodes::Equality.new(@table[:body], Arel::Nodes::Casted.new("hello", @table[:body]))
      sql = oracle.accept(node, Arel::Collectors::SQLString.new).value
      expect(sql).to match(/DBMS_LOB\.COMPARE\(.*"BODY".*'hello'.*\)\s*=\s*0/)
    end
  end

  describe "visit_Arel_Nodes_Matches" do
    it "wraps both sides in UPPER() when case_sensitive is false (default)" do
      node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
      sql = compile(node)
      expect(sql).to match(/UPPER\(\s*"TEST_ORACLE_COMMON_LOBS"\."NAME"\s*\)\s+LIKE\s+UPPER\(\s*'foo'\s*\)/)
    end

    it "leaves the SQL as-is when case_sensitive is true" do
      node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, true)
      sql = compile(node)
      expect(sql).not_to match(/UPPER/)
      expect(sql).to match(/"NAME"\s+LIKE\s+'foo'/)
    end

    it "wraps both sides in UPPER() the same way via Arel::Visitors::Oracle" do
      oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
      node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
      sql = oracle.accept(node, Arel::Collectors::SQLString.new).value
      expect(sql).to match(/UPPER\(\s*"TEST_ORACLE_COMMON_LOBS"\."NAME"\s*\)\s+LIKE\s+UPPER\(\s*'foo'\s*\)/)
    end
  end
end
