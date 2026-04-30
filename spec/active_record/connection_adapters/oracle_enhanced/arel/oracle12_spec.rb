# frozen_string_literal: true

describe "Arel::Visitors::Oracle12" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(:users)
  end

  def compile(node)
    @visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  it "modifies except to be minus" do
    left = Arel::Nodes::SqlLiteral.new("SELECT * FROM users WHERE age > 10")
    right = Arel::Nodes::SqlLiteral.new("SELECT * FROM users WHERE age > 20")
    sql = compile Arel::Nodes::Except.new(left, right)
    expect(sql).to be_like %{
      ( SELECT * FROM users WHERE age > 10 MINUS SELECT * FROM users WHERE age > 20 )
    }
  end

  it "generates select options offset then limit" do
    stmt = Arel::Nodes::SelectStatement.new
    stmt.offset = Arel::Nodes::Offset.new(1)
    stmt.limit = Arel::Nodes::Limit.new(10)
    expect(compile(stmt)).to be_like "SELECT OFFSET 1 ROWS FETCH FIRST 10 ROWS ONLY"
  end

  describe "locking" do
    it "raises ArgumentError if limit and lock are used" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.limit = Arel::Nodes::Limit.new(10)
      stmt.lock = Arel::Nodes::Lock.new(Arel.sql("FOR UPDATE"))
      expect { compile(stmt) }.to raise_error(ArgumentError)
    end

    it "defaults to FOR UPDATE when locking" do
      node = Arel::Nodes::Lock.new(Arel.sql("FOR UPDATE"))
      expect(compile(node)).to be_like "FOR UPDATE"
    end
  end

  describe "Nodes::BindParam" do
    it "increments each bind param" do
      query = @table[:name].eq(Arel::Nodes::BindParam.new(1))
        .and(@table[:id].eq(Arel::Nodes::BindParam.new(1)))
      expect(compile(query)).to be_like %{
        "users"."name" = :a1 AND "users"."id" = :a2
      }
    end
  end

  describe "Nodes::IsNotDistinctFrom" do
    it "should construct a valid generic SQL statement" do
      test = @table[:name].is_not_distinct_from "Aaron Patterson"
      expect(compile(test)).to be_like %{
        DECODE("users"."name", 'Aaron Patterson', 0, 1) = 0
      }
    end

    it "should handle column names on both sides" do
      test = @table[:first_name].is_not_distinct_from @table[:last_name]
      expect(compile(test)).to be_like %{
        DECODE("users"."first_name", "users"."last_name", 0, 1) = 0
      }
    end

    it "should handle nil" do
      val = Arel::Nodes.build_quoted(nil, @table[:active])
      sql = compile Arel::Nodes::IsNotDistinctFrom.new(@table[:name], val)
      expect(sql).to be_like %{ "users"."name" IS NULL }
    end
  end

  describe "Nodes::IsDistinctFrom" do
    it "should handle column names on both sides" do
      test = @table[:first_name].is_distinct_from @table[:last_name]
      expect(compile(test)).to be_like %{
        DECODE("users"."first_name", "users"."last_name", 0, 1) = 1
      }
    end

    it "should handle nil" do
      val = Arel::Nodes.build_quoted(nil, @table[:active])
      sql = compile Arel::Nodes::IsDistinctFrom.new(@table[:name], val)
      expect(sql).to be_like %{ "users"."name" IS NOT NULL }
    end
  end
end
