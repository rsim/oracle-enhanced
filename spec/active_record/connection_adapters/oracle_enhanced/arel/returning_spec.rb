# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon with returning" do
  include ArelVisitorSpecHelper

  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :users, force: true do |t|
        t.string :name
      end
    end
  end

  after(:all) do
    schema_define { drop_table :users, if_exists: true }
    ActiveRecord::Base.clear_cache!
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

  it "compiles an INSERT with returning to RETURNING ... INTO" do
    manager = build_insert.returning([@table[:id], @table[:name]])
    expect(compile(manager.ast)).to end_with(%(RETURNING "USERS"."ID", "USERS"."NAME" INTO :a1, :a2))
  end

  it "compiles an UPDATE with returning to RETURNING ... INTO" do
    manager = build_update.returning([Arel.sql('"NAME"')])
    expect(compile(manager.ast)).to end_with(%(RETURNING "NAME" INTO :a1))
  end

  it "compiles a DELETE with returning to RETURNING ... INTO" do
    manager = build_delete.returning([@table[:name]])
    expect(compile(manager.ast)).to end_with(%(RETURNING "USERS"."NAME" INTO :a1))
  end

  it "raises ArgumentError for returning an expression that is not a column" do
    manager = build_update.returning(Arel.star)
    expect { compile(manager.ast) }.to raise_error(ArgumentError, /Oracle can only return columns of users/)
  end

  [true, false].each do |prepared|
    it "reads the OUT binds of a DELETE with returning#{" without prepared statements" unless prepared}" do
      conn = ActiveRecord::Base.lease_connection
      conn.insert(Arel::InsertManager.new.into(@table).tap { |im| im.insert([[@table[:id], 1], [@table[:name], "foo"]]) })
      manager = build_delete.returning([@table[:id], @table[:name]])

      result = prepared ? conn.select_all(manager) : conn.unprepared_statement { conn.select_all(manager) }

      expect(result.columns).to eq(%w[id name])
      expect(result.rows).to eq([[1, "foo"]])
    end
  end

  it "compiles an INSERT without returning" do
    expect(compile(build_insert.ast)).to start_with("INSERT INTO")
  end
end
