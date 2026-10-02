# frozen_string_literal: true

RSpec.describe "Arel::Visitors::OracleCommon with returning" do
  include ArelVisitorSpecHelper
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :users, force: true do |t|
        t.string :name
        t.date :born_on
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

  after(:each) do
    ActiveRecord::Base.lease_connection.delete("DELETE FROM users")
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
    expect { compile(manager.ast) }.to raise_error(ArgumentError, /Oracle can only return columns of the target table/)
  end

  it "raises ArgumentError for returning a column of another table" do
    manager = build_update.returning([Arel::Table.new(name: :posts)[:id]])
    expect { compile(manager.ast) }.to raise_error(ArgumentError, /Oracle can only return columns of the target table/)
  end

  it "raises ArgumentError for returning a column whose type cannot be read back" do
    manager = build_update.returning([@table[:born_on]])
    expect { compile(manager.ast) }.to raise_error(ArgumentError, /Oracle can only return columns of the target table/)
  end

  [true, false].each do |prepared|
    context(prepared ? "with prepared statements" : "without prepared statements") do
      def run(prepared)
        conn = ActiveRecord::Base.lease_connection
        prepared ? yield(conn) : conn.unprepared_statement { yield(conn) }
      end

      define_method(:prepared) { prepared }

      def id_bind(value)
        Arel::Nodes::BindParam.new(ActiveRecord::Relation::QueryAttribute.new("id", value, ActiveRecord::Type::Integer.new))
      end

      it "reads the OUT binds of an INSERT with returning" do
        manager = Arel::InsertManager.new.into(@table).tap { |im| im.insert([[@table[:id], 1], [@table[:name], "foo"]]) }.returning([@table[:id], @table[:name]])

        result = run(prepared) { |conn| conn.uncached { conn.select_all(manager) } }

        expect(result.rows).to eq([[1, "foo"]])
      end

      it "reads the OUT binds of an UPDATE with returning after its other binds" do
        run(prepared) { |conn| conn.insert(Arel::InsertManager.new.into(@table).tap { |im| im.insert([[@table[:id], 1], [@table[:name], "foo"]]) }) }
        manager = Arel::UpdateManager.new.table(@table).set([[@table[:name], "bar"]]).where(@table[:id].eq(id_bind(1))).returning([@table[:id], @table[:name]])

        result = run(prepared) { |conn| conn.uncached { conn.select_all(manager) } }

        expect(result.rows).to eq([[1, "bar"]])
      end

      it "reads the OUT binds of a DELETE with returning" do
        run(prepared) { |conn| conn.insert(Arel::InsertManager.new.into(@table).tap { |im| im.insert([[@table[:id], 1], [@table[:name], "foo"]]) }) }
        manager = build_delete.returning([@table[:id], @table[:name]])

        result = run(prepared) { |conn| conn.uncached { conn.select_all(manager) } }

        expect(result.columns).to eq(%w[id name])
        expect(result.rows).to eq([[1, "foo"]])
      end
    end
  end

  it "compiles an INSERT without returning" do
    expect(compile(build_insert.ast)).to start_with("INSERT INTO")
  end
end
