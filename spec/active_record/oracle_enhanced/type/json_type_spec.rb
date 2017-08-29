# frozen_string_literal: true

describe "OracleEnhancedAdapter attribute API support for JSON type" do

  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
    @oracle12c_or_higher = !! @conn.select_value(
      "select * from product_component_version where product like 'Oracle%' and to_number(substr(version,1,2)) >= 12")
    skip "Not supported in this database version" unless @oracle12c_or_higher
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_posts, force: true do |t|
        t.string  :title
        t.text    :article
      end
      execute "alter table test_posts add constraint test_posts_title_is_json check (title is json)"
      execute "alter table test_posts add constraint test_posts_article_is_json check (article is json)"
    end

    class ::TestPost < ActiveRecord::Base
      attribute :title, :json
      attribute :article, :json
    end
  end

  after(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      drop_table :test_posts, if_exists: true
    end
  end

  before(:each) do
    TestPost.delete_all
  end

  it "should support attribute api for JSON" do
    post = TestPost.create!(title: { "publish" => true, "foo" => "bar" }, article: { "bar" => "baz" })
    post.reload
    expect(post.title).to eq ({ "publish" => true, "foo" => "bar" })
    expect(post.article).to eq ({ "bar" => "baz" })
    post.title = ({ "publish" => false, "foo" => "bar2" })
    post.save
    expect(post.reload.title).to eq ({ "publish" => false, "foo" => "bar2" })
  end

  it "should support IS JSON" do
    TestPost.create!(title: { "publish" => true, "foo" => "bar" })
    count_json = TestPost.where("title is json")
    expect(count_json.size).to eq 1
    count_non_json = TestPost.where("title is not json")
    expect(count_non_json.size).to eq 0
  end
end
