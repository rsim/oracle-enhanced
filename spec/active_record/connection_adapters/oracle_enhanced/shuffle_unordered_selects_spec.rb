# frozen_string_literal: true

RSpec.describe "OracleEnhancedAdapter shuffle unordered selects" do
  include SchemaSpecHelper

  SAMPLES = 10

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_posts, force: true do |t|
        t.string :title
      end
    end
    class ::TestPost < ActiveRecord::Base
    end
    TestPost.transaction do
      (1..10).each do |id|
        TestPost.create!(id: id, title: "Title #{id}")
      end
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_posts
    end
    Object.send(:remove_const, "TestPost")
    ActiveRecord::Base.clear_cache!
  end

  def with_shuffle(value)
    old_value = ActiveRecord.shuffle_unordered_selects
    ActiveRecord.shuffle_unordered_selects = value
    yield
  ensure
    ActiveRecord.shuffle_unordered_selects = old_value
  end

  def sample(&block)
    Array.new(SAMPLES, &block).uniq
  end

  it "shuffles unordered relations" do
    natural = with_shuffle(false) { TestPost.all.map(&:id) }
    orders = with_shuffle(true) { sample { TestPost.all.map(&:id) } }

    expect(orders.size).to be > 1
    orders.each { |ids| expect(ids.sort).to eq(natural.sort) }
  end

  it "shuffles unordered pluck" do
    natural = with_shuffle(false) { TestPost.pluck(:id) }
    orders = with_shuffle(true) { sample { TestPost.pluck(:id) } }

    expect(orders.size).to be > 1
    orders.each { |ids| expect(ids.sort).to eq(natural.sort) }
  end

  it "leaves ordered relations alone" do
    natural = with_shuffle(false) { TestPost.order(:id).map(&:id) }

    expect(with_shuffle(true) { sample { TestPost.order(:id).map(&:id) } }).to eq([natural])
  end

  it "leaves raw SQL alone" do
    sql = TestPost.all.to_sql
    natural = with_shuffle(false) { TestPost.find_by_sql(sql).map(&:id) }

    expect(with_shuffle(true) { sample { TestPost.find_by_sql(sql).map(&:id) } }).to eq([natural])
  end
end
