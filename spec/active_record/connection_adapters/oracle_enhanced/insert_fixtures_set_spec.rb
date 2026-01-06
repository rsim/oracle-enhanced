# frozen_string_literal: true

describe "OracleEnhancedAdapter insert_fixtures_set" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection

    @conn.execute "DROP TABLE test_posts" rescue nil
    @conn.execute <<~SQL
      CREATE TABLE test_posts (
        id          NUMBER PRIMARY KEY,
        title       VARCHAR2(100),
        content     CLOB,
        ncontent    NCLOB,
        attachment  BLOB
      )
    SQL

    @conn.execute "DROP SEQUENCE test_posts_seq" rescue nil
    @conn.execute <<~SQL
      CREATE SEQUENCE test_posts_seq MINVALUE 1
        INCREMENT BY 1 START WITH 1 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE test_posts"
    @conn.execute "DROP SEQUENCE test_posts_seq"
  end

  before(:each) do
    class ::TestPost < ActiveRecord::Base
      self.table_name = "test_posts"
    end
  end

  after(:each) do
    @conn.execute "DELETE FROM test_posts"
    Object.send(:remove_const, "TestPost")
    ActiveRecord::Base.clear_cache!
  end

  it "inserts fixture rows with LOB columns" do
    large_clob = "Large CLOB" * 10000
    large_nclob = "Large NCLOB" * 10000
    large_blob = Random.bytes(512.kilobytes)

    fixture_set = {
      "test_posts" => [
        { "id" => 1, "title" => "First Post", "content" => "CLOB content", "ncontent" => "NCLOB content", "attachment" => "binary data" },
        { "id" => 2, "title" => "Second Post", "content" => large_clob, "ncontent" => large_nclob, "attachment" => large_blob },
      ]
    }

    @conn.insert_fixtures_set(fixture_set)

    expect(TestPost.count).to eq(2)

    first_post = TestPost.find_by!(title: "First Post")
    expect(first_post.id).to be_present

    second_post = TestPost.find_by!(title: "Second Post")
    expect(second_post.id).to be_present
    expect(second_post.content).to eq(large_clob)
    expect(second_post.ncontent).to eq(large_nclob)
    expect(second_post.attachment).to eq(large_blob)
  end
end
