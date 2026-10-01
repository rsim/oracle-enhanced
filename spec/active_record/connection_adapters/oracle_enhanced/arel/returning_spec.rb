# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon with returning" do
  include ArelVisitorSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  before(:each) do
    @visitor = oracle_visitor(fetch_first: true)
    @table = Arel::Table.new(name: :users)
  end

  def compile(node)
    @visitor.accept(node, Arel::Collectors::SQLString.new).value
  end

  def build_insert
    Arel::InsertManager.new.into(@table).tap do |im|
      im.insert([[@table[:name], "foo"]])
    end
  end

  def build_update
    Arel::UpdateManager.new.table(@table).tap do |um|
      um.set([[@table[:name], "foo"]])
      um.where(@table[:id].eq(1))
    end
  end

  def build_delete
    Arel::DeleteManager.new.from(@table).tap do |dm|
      dm.where(@table[:id].eq(1))
    end
  end

  it "raises ArgumentError for an INSERT with returning and points to Active Record's insert" do
    manager = build_insert.returning(Arel.star)
    expect { compile(manager.ast) }.to raise_error(ArgumentError, /returning on INSERT\. Pass returning: to Active Record's insert/)
  end

  it "raises ArgumentError for an UPDATE with returning" do
    manager = build_update.returning(Arel.star)
    expect { compile(manager.ast) }.to raise_error(ArgumentError, "Oracle does not support Arel's returning on UPDATE.")
  end

  it "raises ArgumentError for a DELETE with returning" do
    manager = build_delete.returning(Arel.star)
    expect { compile(manager.ast) }.to raise_error(ArgumentError, "Oracle does not support Arel's returning on DELETE.")
  end

  it "compiles an INSERT without returning" do
    expect(compile(build_insert.ast)).to start_with("INSERT INTO")
  end
end
