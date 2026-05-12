# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon#visit_Arel_Nodes_Matches preserves the input node" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(:users)
  end

  def compile(node, visitor: @visitor)
    visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  it "leaves the original Matches node's left attribute unchanged" do
    node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
    original_left = node.left
    compile(node)
    expect(node.left).to equal(original_left)
  end

  it "leaves the original Matches node's right attribute unchanged" do
    node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
    original_right = node.right
    compile(node)
    expect(node.right).to equal(original_right)
  end

  it "produces the same SQL when the same Matches node is compiled twice" do
    node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
    sql1 = compile(node)
    sql2 = compile(node)
    expect(sql2).to eq(sql1)
  end

  it "does not double-wrap in UPPER when compiled twice" do
    node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
    compile(node)
    sql = compile(node)
    expect(sql.scan(/UPPER\(/).size).to eq(2)
    expect(sql).not_to match(/UPPER\(\s*UPPER\(/)
  end

  it "preserves the input node the same way via Arel::Visitors::Oracle" do
    oracle = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    node = Arel::Nodes::Matches.new(@table[:name], Arel.sql("'foo'"), nil, false)
    original_left = node.left
    original_right = node.right
    compile(node, visitor: oracle)
    expect(node.left).to equal(original_left)
    expect(node.right).to equal(original_right)
  end
end
