require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

# This is a scenario you may hit if you are generating a report to download with many, many rows
describe 'avoiding ORA-01795: maximum number of expressions in a list is 1000' do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  before(:all) do
    schema_define do
      create_table :posts do |t|
        t.string      :body
      end
      create_table :comments do |t|
        t.string      :comment
        t.integer     :post_id
      end
      create_table :tags do |t|
        t.string      :name
      end
      create_table :posts_tags, :id=>false do |t|
        t.integer     :post_id
        t.integer     :tag_id
      end
    end
    class ::Comment < ActiveRecord::Base; end
    class ::Tag < ActiveRecord::Base; end
    class ::Post < ActiveRecord::Base
      has_many :comments
      has_and_belongs_to_many :tags
    end
  end

  after(:all) do
    schema_define do
      drop_table :comments
      drop_table :posts
      drop_table :tags
      drop_table :posts_tags
    end
    Object.send(:remove_const, "Post")
    Object.send(:remove_const, "Comment")
    Object.send(:remove_const, "Tag")
  end


  it 'should split a has_many :include into multiple requests to avoid 1000 limit' do
    1001.times { Post.create(:comments=>[Comment.new]) }

    lambda {
      Post.all(:include=>:comments)
    }.should_not raise_error ActiveRecord::StatementInvalid, /ORA-01795/
  end

  it 'should split HABTM :include into multiple requests to avoid 1000 limit' do
    1001.times { Post.create(:tags=>[Tag.new])}

    lambda {
      Post.all(:include=>:tags)
    }.should_not raise_error ActiveRecord::StatementInvalid, /ORA-01795/
  end
end