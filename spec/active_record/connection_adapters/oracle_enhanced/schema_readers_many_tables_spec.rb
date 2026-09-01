# frozen_string_literal: true

require "spec_helper"

# Ported from activerecord/test/cases/connection_adapters/schema_statements_test.rb
# (rails/rails#58421, #58494, #58498): each schema reader also accepts an Array of table names
# and answers with a Hash keyed by the names it was given.
RSpec.describe "OracleEnhancedAdapter schema readers for many tables" do
  include SchemaSpecHelper

  READERS = %i[columns primary_keys indexes foreign_keys check_constraints unique_constraints table_options].freeze
  TABLES = %w[test_reader_parents test_reader_children].freeze

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.lease_connection
    schema_define do
      create_table :test_reader_parents, force: true, comment: "reader parents" do |t|
        t.string :code
        t.unique_constraint :code, name: "test_reader_parents_code_uq"
      end
      create_table :test_reader_children, force: true do |t|
        t.references :test_reader_parent, foreign_key: true
        t.string :name
        t.index :name, name: "test_reader_children_name_idx"
        t.check_constraint "LENGTH(name) > 0", name: "test_reader_children_name_chk"
      end
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_reader_children, if_exists: true
      drop_table :test_reader_parents, if_exists: true
    end
  end

  def attributes(definitions)
    Array(definitions).map { |definition| definition.is_a?(String) ? definition : definition.instance_values }
  end

  it "a list reads exactly the tables it is given" do
    READERS.each do |reader|
      expect(@conn.public_send(reader, TABLES).keys).to match_array(TABLES), "#{reader} did not answer for the tables it was given"
    end
  end

  it "a list returns what asking for each table returns" do
    READERS.each do |reader|
      listed = @conn.public_send(reader, TABLES)
      TABLES.each do |table|
        expect(attributes(listed[table])).to eq(attributes(@conn.public_send(reader, table))), "#{reader} answered differently for #{table} in a list"
      end
    end
  end

  it "a list reads columns in the same order as one table" do
    listed = @conn.columns(TABLES)
    TABLES.each do |table|
      expect(listed[table].map(&:name)).to eq(@conn.columns(table).map(&:name))
    end
  end

  it "an empty list reads nothing" do
    READERS.each do |reader|
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }
      result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        @conn.public_send(reader, [])
      end
      expect(result).to eq({})
      expect(queries).to be_empty, "#{reader}([]) queried the database"
    end
  end

  it "a list keys each table by the name it was given" do
    given = "TEST_READER_CHILDREN"
    READERS.each do |reader|
      listed = @conn.public_send(reader, [given])
      expect(listed.keys).to eq([given]), "#{reader} did not key by the name it was given"
      expect(attributes(listed[given])).to eq(attributes(@conn.public_send(reader, given)))
    end
    expect(@conn.foreign_keys([given])[given]).not_to be_empty
  end
end
