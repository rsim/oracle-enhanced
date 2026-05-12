# frozen_string_literal: true

RSpec.describe "Arel::Visitors::Oracle literal limit/offset via value_before_type_cast" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = Arel::Visitors::Oracle.new(ActiveRecord::Base.connection)
    @table = Arel::Table.new(:users)
  end

  def compile(node)
    @visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  describe "value_before_type_cast helper" do
    it "returns the value unchanged when the argument does not respond to value_before_type_cast" do
      expect(@visitor.send(:value_before_type_cast, 42)).to eq(42)
    end

    it "unwraps an object that responds to value_before_type_cast" do
      casted = Arel::Nodes::Casted.new(7, @table[:id])
      expect(@visitor.send(:value_before_type_cast, casted)).to eq(7)
    end
  end

  describe "bind_limit_offset? helper" do
    it "returns true when the limit expr exposes ActiveModel::Type::Value via #type" do
      typed = Struct.new(:type).new(ActiveModel::Type::Value.new)
      expect(@visitor.send(:bind_limit_offset?, typed, 10)).to be(true)
    end

    it "returns true when the offset expr exposes ActiveModel::Type::Value via #type" do
      typed = Struct.new(:type).new(ActiveModel::Type::Value.new)
      expect(@visitor.send(:bind_limit_offset?, 5, typed)).to be(true)
    end

    it "returns false when neither limit nor offset is a BindParam or typed-Value" do
      expect(@visitor.send(:bind_limit_offset?, 5, 10)).to be(false)
    end
  end

  describe "SELECT with both limit and offset" do
    it "renders plain Integer limit+offset as literals summed into the rownum upper bound" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.limit = Arel::Nodes::Limit.new(5)
      stmt.offset = Arel::Nodes::Offset.new(10)
      sql = compile(stmt)
      expect(sql).to include("rownum <= 15")
      expect(sql).to include("raw_rnum_ > 10")
      expect(sql).not_to match(/:a\d/)
    end

    it "unwraps Arel::Nodes::Casted limit+offset via value_before_type_cast" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.limit = Arel::Nodes::Limit.new(Arel::Nodes::Casted.new(5, @table[:id]))
      stmt.offset = Arel::Nodes::Offset.new(Arel::Nodes::Casted.new(10, @table[:id]))
      sql = compile(stmt)
      expect(sql).to include("rownum <= 15")
      expect(sql).to include("raw_rnum_ > 10")
      expect(sql).not_to match(/:a\d/)
    end

    it "switches to the bind path when both limit and offset are BindParams" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.limit = Arel::Nodes::Limit.new(Arel::Nodes::BindParam.new(5))
      stmt.offset = Arel::Nodes::Offset.new(Arel::Nodes::BindParam.new(10))
      sql = compile(stmt)
      expect(sql).to match(/:a\d/)
      expect(sql).not_to match(/rownum <= 15/)
    end

    it "switches to the bind path when only the offset arrives as a BindParam" do
      stmt = Arel::Nodes::SelectStatement.new
      stmt.limit = Arel::Nodes::Limit.new(5)
      stmt.offset = Arel::Nodes::Offset.new(Arel::Nodes::BindParam.new(10))
      sql = compile(stmt)
      expect(sql).to match(/:a\d/)
      expect(sql).not_to match(/rownum <= 15/)
    end
  end
end
