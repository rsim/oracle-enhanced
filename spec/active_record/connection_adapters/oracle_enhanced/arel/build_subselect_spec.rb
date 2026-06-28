# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon#build_subselect" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(name: :users)
  end

  def build_delete(orders: [], limit: nil, offset: nil, wheres: [])
    stmt = Arel::Nodes::DeleteStatement.new
    stmt.relation = @table
    stmt.wheres = wheres
    stmt.orders = orders
    stmt.limit = limit
    stmt.offset = offset
    stmt
  end

  it "drops orders on the subselect to avoid ORA-00907" do
    delete = build_delete(orders: [@table[:id].asc], limit: Arel::Nodes::Limit.new(10))
    subselect = @visitor.send(:build_subselect, @table[:id], delete)
    expect(subselect.orders).to eq([])
  end

  it "leaves the original DeleteStatement's orders unmodified" do
    orders = [@table[:id].asc]
    delete = build_delete(orders: orders, limit: Arel::Nodes::Limit.new(10))
    @visitor.send(:build_subselect, @table[:id], delete)
    expect(delete.orders).to eq(orders)
  end

  it "preserves limit, offset, wheres, and projections from super" do
    limit = Arel::Nodes::Limit.new(10)
    offset = Arel::Nodes::Offset.new(5)
    wheres = [@table[:name].eq("foo")]
    delete = build_delete(orders: [@table[:id].asc], limit: limit, offset: offset, wheres: wheres)

    subselect = @visitor.send(:build_subselect, @table[:id], delete)
    core = subselect.cores.first
    expect(subselect.limit).to eq(limit)
    expect(subselect.offset).to eq(offset)
    expect(core.wheres).to eq(wheres)
    expect(core.projections).to eq([@table[:id]])
    expect(core.from).to eq(@table)
  end

  it "drops orders the same way via Arel::Visitors::Oracle" do
    oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    delete = build_delete(orders: [@table[:id].asc], limit: Arel::Nodes::Limit.new(10))
    subselect = oracle.send(:build_subselect, @table[:id], delete)
    expect(subselect.orders).to eq([])
  end
end
