# frozen_string_literal: true

describe "Arel::Visitors::Oracle12" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  let(:visitor) { Arel::Visitors::Oracle12.new(ActiveRecord::Base.connection) }
  let(:table) { Arel::Table.new(:users) }

  describe "visit_Arel_Nodes_HomogeneousIn" do
    it "marks the collector as not preparable" do
      node = Arel::Nodes::HomogeneousIn.new([1, 2, 3], table[:id], :in)
      collector = Arel::Collectors::SQLString.new
      collector.preparable = true
      visitor.accept(node, collector)
      expect(collector.preparable).to eq(false)
    end
  end
end

describe "Arel::Visitors::Oracle" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  let(:visitor) { Arel::Visitors::Oracle.new(ActiveRecord::Base.connection) }
  let(:table) { Arel::Table.new(:users) }

  describe "visit_Arel_Nodes_HomogeneousIn" do
    it "marks the collector as not preparable" do
      node = Arel::Nodes::HomogeneousIn.new([1, 2, 3], table[:id], :in)
      collector = Arel::Collectors::SQLString.new
      collector.preparable = true
      visitor.accept(node, collector)
      expect(collector.preparable).to eq(false)
    end
  end
end
