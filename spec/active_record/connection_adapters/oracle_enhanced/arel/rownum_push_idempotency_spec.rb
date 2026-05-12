# frozen_string_literal: true

RSpec.describe "Arel::Visitors::Oracle limit-only ROWNUM rewrite preserves the input SelectStatement" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
  end

  def compile(node, visitor: @visitor)
    visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  def build_limit_only_select
    stmt = Arel::Nodes::SelectStatement.new
    stmt.limit = Arel::Nodes::Limit.new(10)
    stmt
  end

  it "leaves the original SelectCore's wheres array reference unchanged" do
    stmt = build_limit_only_select
    original_wheres = stmt.cores.last.wheres
    compile(stmt)
    expect(stmt.cores.last.wheres).to equal(original_wheres)
  end

  it "does not push the ROWNUM clause onto the original wheres array" do
    stmt = build_limit_only_select
    compile(stmt)
    expect(stmt.cores.last.wheres).to be_empty
  end

  it "produces the same SQL when the same SelectStatement is compiled twice" do
    stmt = build_limit_only_select
    sql1 = compile(stmt)
    sql2 = compile(stmt)
    expect(sql2).to eq(sql1)
  end

  it "does not accumulate ROWNUM clauses when compiled twice" do
    stmt = build_limit_only_select
    compile(stmt)
    sql = compile(stmt)
    expect(sql.scan(/ROWNUM\b/i).size).to eq(1)
  end

  it "still emits the ROWNUM upper bound in the compiled SQL" do
    stmt = build_limit_only_select
    sql = compile(stmt)
    expect(sql).to match(/ROWNUM\s*<=\s*10/i)
  end
end
