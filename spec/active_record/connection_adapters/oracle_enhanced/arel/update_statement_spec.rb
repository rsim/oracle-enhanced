# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon#visit_Arel_Nodes_UpdateStatement" do
  include ArelVisitorSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = oracle_visitor(fetch_first: true)
    @table = Arel::Table.new(name: :users)
  end

  def compile(node, visitor: @visitor)
    visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  def build_update(orders: [], limit: nil)
    stmt = Arel::Nodes::UpdateStatement.new
    stmt.relation = @table
    stmt.values = [Arel::Nodes::Assignment.new(@table[:name], Arel.sql("'foo'"))]
    stmt.orders = orders
    stmt.limit = limit
    stmt
  end

  it "drops ORDER BY when no LIMIT is set" do
    stmt = build_update(orders: [Arel.sql("id ASC")])
    sql = compile(stmt)
    expect(sql).not_to match(/ORDER BY/i)
  end

  it "moves LIMIT into a subquery on the key and drops ORDER BY" do
    stmt = build_update(orders: [Arel.sql("id ASC")], limit: Arel::Nodes::Limit.new(10))
    stmt.key = @table[:id]
    sql = compile(stmt)
    expect(sql).to match(/WHERE \("USERS"\."ID"\) IN \(SELECT/i)
    expect(sql).not_to match(/ORDER BY/i)
  end

  { "ROWNUM" => false, "the row limiting clause" => true }.each do |syntax, fetch_first|
    it "raises ArgumentError for an UPDATE with a LIMIT but no key with #{syntax}" do
      stmt = build_update(orders: [Arel.sql("id ASC")], limit: Arel::Nodes::Limit.new(10))
      expect { compile(stmt, visitor: oracle_visitor(fetch_first: fetch_first)) }.to raise_error(ArgumentError, /UPDATE without a key/)
    end

    it "raises ArgumentError for a DELETE with a LIMIT but no key with #{syntax}" do
      stmt = Arel::Nodes::DeleteStatement.new
      stmt.relation = @table
      stmt.limit = Arel::Nodes::Limit.new(10)
      expect { compile(stmt, visitor: oracle_visitor(fetch_first: fetch_first)) }.to raise_error(ArgumentError, /DELETE without a key/)
    end
  end

  it "leaves the original UpdateStatement's orders unmodified" do
    orders = [Arel.sql("id ASC")]
    stmt = build_update(orders: orders)
    compile(stmt)
    expect(stmt.orders).to eq(orders)
  end

  it "strips ORDER BY the same way via Arel::Visitors::Oracle" do
    oracle = oracle_visitor(fetch_first: false)
    stmt = build_update(orders: [Arel.sql("id ASC")])
    sql = compile(stmt, visitor: oracle)
    expect(sql).not_to match(/ORDER BY/i)
  end

  it "is a no-op when the statement has no orders" do
    stmt = build_update
    sql = compile(stmt)
    expect(sql).not_to match(/ORDER BY/i)
    expect(stmt.orders).to eq([])
  end
end
