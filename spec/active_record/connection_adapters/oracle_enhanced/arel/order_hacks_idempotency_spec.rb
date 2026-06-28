# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon#order_hacks preserves the input SelectStatement" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(name: :users)
  end

  def compile(node, visitor: @visitor)
    visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  def build_first_value_select(order_literal = "foo")
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(
      "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    )
    stmt.orders << Arel::Nodes::SqlLiteral.new(order_literal)
    stmt
  end

  it "leaves the original SelectStatement's orders array reference unchanged" do
    stmt = build_first_value_select
    original_orders = stmt.orders
    compile(stmt)
    expect(stmt.orders).to equal(original_orders)
  end

  it "leaves the original order entries unchanged" do
    stmt = build_first_value_select
    original_first = stmt.orders.first
    compile(stmt)
    expect(stmt.orders.first).to equal(original_first)
    expect(stmt.orders.first.to_s).to eq("foo")
  end

  it "produces the same SQL when the same SelectStatement is compiled twice" do
    stmt = build_first_value_select
    sql1 = compile(stmt)
    sql2 = compile(stmt)
    expect(sql2).to eq(sql1)
  end

  it "rewrites the order to alias_0__ in the compiled SQL while leaving the input intact" do
    stmt = build_first_value_select
    sql = compile(stmt)
    expect(sql).to match(/ORDER BY\s+alias_0__/)
    expect(stmt.orders.first.to_s).to eq("foo")
  end

  it "preserves NULLS FIRST/LAST in the original order while emitting it in the compiled SQL" do
    stmt = build_first_value_select("foo DESC NULLS LAST")
    original_first = stmt.orders.first
    sql = compile(stmt)
    expect(sql).to match(/ORDER BY\s+alias_0__\s+DESC\s+NULLS\s+LAST/)
    expect(stmt.orders.first).to equal(original_first)
    expect(stmt.orders.first.to_s).to eq("foo DESC NULLS LAST")
  end
end
