# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon#visit_Arel_Nodes_HomogeneousIn" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection)
    type_caster = Class.new { def type_for_attribute(_name) = ActiveRecord::Type::Value.new }.new
    @table = Arel::Table.new(name: :users, type_caster: type_caster)
  end

  def compile(node, visitor: @visitor)
    visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  it "marks the collector as not preparable" do
    node = Arel::Nodes::HomogeneousIn.new([1, 2, 3], @table[:id], :in)
    collector = Arel::Collectors::SQLString.new
    collector.preparable = true
    @visitor.accept(node, collector)
    expect(collector.preparable).to be(false)
  end

  it "renders :in as a literal IN list" do
    node = Arel::Nodes::HomogeneousIn.new([1, 2, 3], @table[:id], :in)
    expect(compile(node)).to match(/"USERS"\."ID"\s+IN\s+\(1,2,3\)/)
  end

  it "renders :notin as a literal NOT IN list" do
    node = Arel::Nodes::HomogeneousIn.new([1, 2, 3], @table[:id], :notin)
    expect(compile(node)).to match(/"USERS"\."ID"\s+NOT IN\s+\(1,2,3\)/)
  end

  it "falls back to NULL when :in has an empty values array" do
    node = Arel::Nodes::HomogeneousIn.new([], @table[:id], :in)
    expect(compile(node)).to match(/"USERS"\."ID"\s+IN\s+\(NULL\)/)
  end

  it "falls back to NULL when :notin has an empty values array" do
    node = Arel::Nodes::HomogeneousIn.new([], @table[:id], :notin)
    expect(compile(node)).to match(/"USERS"\."ID"\s+NOT IN\s+\(NULL\)/)
  end

  it "chunks :in into multiple IN groups joined by OR when values exceed in_clause_length" do
    node = Arel::Nodes::HomogeneousIn.new((1..1001).to_a, @table[:id], :in)
    sql = compile(node)
    expect(sql.scan(/"USERS"\."ID" IN \(/).size).to eq(2)
    expect(sql).to include(" OR ")
    expect(sql).to start_with("(")
    expect(sql).to end_with(")")
    expect(sql).to include("IN (1001)")
  end

  it "chunks :notin into multiple NOT IN groups joined by AND when values exceed in_clause_length" do
    node = Arel::Nodes::HomogeneousIn.new((1..1001).to_a, @table[:id], :notin)
    sql = compile(node)
    expect(sql.scan(/"USERS"\."ID" NOT IN \(/).size).to eq(2)
    expect(sql).to include(" AND ")
    expect(sql).to start_with("(")
    expect(sql).to end_with(")")
    expect(sql).to include("NOT IN (1001)")
  end

  it "chunks :in the same way via Arel::Visitors::Oracle" do
    oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    node = Arel::Nodes::HomogeneousIn.new((1..1001).to_a, @table[:id], :in)
    sql = compile(node, visitor: oracle)
    expect(sql.scan(/"USERS"\."ID" IN \(/).size).to eq(2)
    expect(sql).to include(" OR ")
  end

  it "chunks :notin the same way via Arel::Visitors::Oracle" do
    oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    node = Arel::Nodes::HomogeneousIn.new((1..1001).to_a, @table[:id], :notin)
    sql = compile(node, visitor: oracle)
    expect(sql.scan(/"USERS"\."ID" NOT IN \(/).size).to eq(2)
    expect(sql).to include(" AND ")
  end
end
