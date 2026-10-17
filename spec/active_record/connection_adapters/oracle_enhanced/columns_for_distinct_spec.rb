# frozen_string_literal: true

describe "OracleEnhancedAdapter#columns_for_distinct" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  it "joins composite primary key columns in PARTITION BY" do
    sql = @conn.columns_for_distinct(["posts.id", "posts.tenant_id"], ["posts.created_at DESC"])
    expect(sql).to include("PARTITION BY posts.id, posts.tenant_id")
  end
end
