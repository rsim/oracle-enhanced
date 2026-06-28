# frozen_string_literal: true

RSpec.describe "Arel::Visitors::Oracle" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(name: :users)
  end

  def compile(node)
    @visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  it "modifies order when there is distinct and first value" do
    select = "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
    stmt.orders << Arel::Nodes::SqlLiteral.new("foo")

    expect(compile(stmt)).to be_like %{
      SELECT #{select} ORDER BY alias_0__
    }
  end

  it "is idempotent with crazy query" do
    select = "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
    stmt.orders << Arel::Nodes::SqlLiteral.new("foo")

    sql = compile(stmt)
    expect(compile(stmt)).to eq(sql)
  end

  it "splits orders with commas" do
    select = "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
    stmt.orders << Arel::Nodes::SqlLiteral.new("foo, bar")

    expect(compile(stmt)).to be_like %{
      SELECT #{select} ORDER BY alias_0__, alias_1__
    }
  end

  it "splits orders with commas and function calls" do
    select = "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
    stmt.orders << Arel::Nodes::SqlLiteral.new("NVL(LOWER(bar, foo), foo) DESC, UPPER(baz)")

    expect(compile(stmt)).to be_like %{
      SELECT #{select} ORDER BY alias_0__ DESC, alias_1__
    }
  end

  it "leaves collector.retryable true after the DISTINCT+FIRST_VALUE ORDER BY rewrite" do
    select = "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__"
    stmt = Arel::Nodes::SelectStatement.new
    stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select, retryable: true)
    stmt.orders << Arel::Nodes::SqlLiteral.new("foo", retryable: true)
    collector = Arel::Collectors::SQLString.new
    collector.retryable = true
    @visitor.accept(stmt, collector)
    expect(collector.retryable).to be(true)
  end

  describe "order_hacks NULLS handling" do
    let(:select) { "DISTINCT foo.id, FIRST_VALUE(projects.name) OVER (foo) AS alias_0__" }

    def select_with_order(order_clause)
      stmt = Arel::Nodes::SelectStatement.new
      stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
      stmt.orders << Arel::Nodes::SqlLiteral.new(order_clause)
      stmt
    end

    it "preserves NULLS FIRST on the rewritten alias" do
      expect(compile(select_with_order("foo NULLS FIRST"))).to be_like %{
        SELECT #{select} ORDER BY alias_0__ NULLS FIRST
      }
    end

    it "preserves NULLS LAST on the rewritten alias" do
      expect(compile(select_with_order("foo NULLS LAST"))).to be_like %{
        SELECT #{select} ORDER BY alias_0__ NULLS LAST
      }
    end

    it "preserves DESC combined with NULLS LAST on the rewritten alias" do
      expect(compile(select_with_order("foo DESC NULLS LAST"))).to be_like %{
        SELECT #{select} ORDER BY alias_0__ DESC NULLS LAST
      }
    end

    it "upcases the NULLS keyword regardless of source casing" do
      expect(compile(select_with_order("foo nulls first"))).to be_like %{
        SELECT #{select} ORDER BY alias_0__ NULLS FIRST
      }
    end

    it "leaves the ORDER BY untouched when no FIRST_VALUE projection is present" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new("foo.id")
      stmt.orders << Arel::Nodes::SqlLiteral.new("foo NULLS FIRST")
      expect(compile(stmt)).to be_like %{
        SELECT foo.id ORDER BY foo NULLS FIRST
      }
    end

    it "returns the SelectStatement unchanged when there are no orders" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new(select)
      expect(compile(stmt)).to be_like %{ SELECT #{select} }
    end
  end

  describe "Nodes::SelectStatement" do
    describe "limit" do
      it "adds a rownum clause" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.limit = Arel::Nodes::Limit.new(10)

        expect(compile(stmt)).to be_like %{ SELECT WHERE ROWNUM <= 10 }
      end

      it "leaves collector.retryable true so the SELECT is retryable end-to-end" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.limit = Arel::Nodes::Limit.new(10)
        collector = Arel::Collectors::SQLString.new
        collector.retryable = true
        @visitor.accept(stmt, collector)
        expect(collector.retryable).to be(true)
      end

      it "is idempotent" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.orders << Arel::Nodes::SqlLiteral.new("foo")
        stmt.limit = Arel::Nodes::Limit.new(10)

        sql = compile(stmt)
        expect(compile(stmt)).to eq(sql)
      end

      it "creates a subquery when there is order_by" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.orders << Arel::Nodes::SqlLiteral.new("foo")
        stmt.limit = Arel::Nodes::Limit.new(10)

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (SELECT ORDER BY foo ) WHERE ROWNUM <= 10
        }
      end

      it "creates a subquery when there is group by" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.cores.first.groups << Arel::Nodes::SqlLiteral.new("foo")
        stmt.limit = Arel::Nodes::Limit.new(10)

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (SELECT GROUP BY foo ) WHERE ROWNUM <= 10
        }
      end

      it "creates a subquery when there is DISTINCT" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.cores.first.set_quantifier = Arel::Nodes::Distinct.new
        stmt.cores.first.projections << Arel::Nodes::SqlLiteral.new("id")
        stmt.limit = Arel::Nodes::Limit.new(10)

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (SELECT DISTINCT id ) WHERE ROWNUM <= 10
        }
      end

      it "creates a different subquery when there is an offset" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.limit = Arel::Nodes::Limit.new(10)
        stmt.offset = Arel::Nodes::Offset.new(10)

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (
            SELECT raw_sql_.*, rownum raw_rnum_
            FROM (SELECT ) raw_sql_
             WHERE rownum <= 20
          )
          WHERE raw_rnum_ > 10
        }
      end

      it "creates a subquery when there is limit and offset with BindParams" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.limit = Arel::Nodes::Limit.new(Arel::Nodes::BindParam.new(1))
        stmt.offset = Arel::Nodes::Offset.new(Arel::Nodes::BindParam.new(1))

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (
            SELECT raw_sql_.*, rownum raw_rnum_
            FROM (SELECT ) raw_sql_
             WHERE rownum <= (:a1 + :a2)
          )
          WHERE raw_rnum_ > :a3
        }
      end

      it "is idempotent with different subquery" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.limit = Arel::Nodes::Limit.new(10)
        stmt.offset = Arel::Nodes::Offset.new(10)

        sql = compile(stmt)
        expect(compile(stmt)).to eq(sql)
      end
    end

    describe "only offset" do
      it "creates a select from subquery with rownum condition" do
        stmt = Arel::Nodes::SelectStatement.new
        stmt.offset = Arel::Nodes::Offset.new(10)

        expect(compile(stmt)).to be_like %{
          SELECT * FROM (
            SELECT raw_sql_.*, rownum raw_rnum_
            FROM (SELECT) raw_sql_
          )
          WHERE raw_rnum_ > 10
        }
      end
    end
  end

  it "modifies except to be minus" do
    left = Arel::Nodes::SqlLiteral.new("SELECT * FROM users WHERE age > 10")
    right = Arel::Nodes::SqlLiteral.new("SELECT * FROM users WHERE age > 20")

    expect(compile(Arel::Nodes::Except.new(left, right))).to be_like %{
      ( SELECT * FROM users WHERE age > 10 MINUS SELECT * FROM users WHERE age > 20 )
    }
  end

  describe "locking" do
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
        "USERS"."NAME" = :a1 AND "USERS"."ID" = :a2
      }
    end
  end

  describe "Nodes::IsNotDistinctFrom" do
    it "constructs a valid generic SQL statement" do
      test = @table[:name].is_not_distinct_from "Aaron Patterson"

      expect(compile(test)).to be_like %{
        DECODE("USERS"."NAME", 'Aaron Patterson', 0, 1) = 0
      }
    end

    it "handles column names on both sides" do
      test = @table[:first_name].is_not_distinct_from @table[:last_name]

      expect(compile(test)).to be_like %{
        DECODE("USERS"."FIRST_NAME", "USERS"."LAST_NAME", 0, 1) = 0
      }
    end

    it "handles nil" do
      val = Arel::Nodes.build_quoted(nil, @table[:active])

      expect(compile(Arel::Nodes::IsNotDistinctFrom.new(@table[:name], val))).to be_like %{
        "USERS"."NAME" IS NULL
      }
    end
  end

  describe "Nodes::IsDistinctFrom" do
    it "handles column names on both sides" do
      test = @table[:first_name].is_distinct_from @table[:last_name]

      expect(compile(test)).to be_like %{
        DECODE("USERS"."FIRST_NAME", "USERS"."LAST_NAME", 0, 1) = 1
      }
    end

    it "handles nil" do
      val = Arel::Nodes.build_quoted(nil, @table[:active])

      expect(compile(Arel::Nodes::IsDistinctFrom.new(@table[:name], val))).to be_like %{
        "USERS"."NAME" IS NOT NULL
      }
    end
  end
end
