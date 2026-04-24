# frozen_string_literal: true

describe "OracleEnhancedAdapter#columns_for_distinct" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  it "strips ASC modifier" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at ASC"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/\bASC\b/i)
  end

  it "strips DESC modifier" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at DESC"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/\bDESC\b/i)
  end

  it "strips NULLS FIRST modifier" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at NULLS FIRST"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/NULLS\s+FIRST/i)
  end

  it "strips NULLS LAST modifier" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at NULLS LAST"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/NULLS\s+LAST/i)
  end

  it "strips combined DESC NULLS LAST" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at DESC NULLS LAST"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/\bDESC\b/i)
    expect(sql).not_to match(/NULLS/i)
  end

  it "strips combined ASC NULLS FIRST" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at ASC NULLS FIRST"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/\bASC\b/i)
    expect(sql).not_to match(/NULLS/i)
  end

  it "strips lowercase desc nulls last" do
    sql = @conn.columns_for_distinct(["posts.id"], ["posts.created_at desc nulls last"])
    expect(sql).to include("FIRST_VALUE(posts.created_at)")
    expect(sql).not_to match(/\bdesc\b/i)
    expect(sql).not_to match(/nulls/i)
  end

  it "joins composite primary key columns in PARTITION BY" do
    sql = @conn.columns_for_distinct(["posts.id", "posts.tenant_id"], ["posts.created_at DESC"])
    expect(sql).to include("PARTITION BY posts.id, posts.tenant_id")
  end

  it "strips DESC NULLS LAST from an Arel ordering node" do
    order_node = Arel::Table.new(:posts)[:created_at].desc.nulls_last
    sql = @conn.columns_for_distinct(["posts.id"], [order_node])
    expect(sql).to match(/FIRST_VALUE\("POSTS"\."CREATED_AT"\)/i)
    expect(sql).not_to match(/\bDESC\b/i)
    expect(sql).not_to match(/NULLS/i)
  end
end
