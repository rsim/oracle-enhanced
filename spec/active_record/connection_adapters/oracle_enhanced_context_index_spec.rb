require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter context index" do
  include SchemaSpecHelper

  before(:all) do
    # database user should have CTXAPP role to be able to set CONTEXT index parameters
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "on single table" do
    before(:all) do
      @title_words = %w{aaa bbb ccc}
      @body_words = %w{foo bar baz}

      schema_define do
        create_table :posts, :force => true do |t|
          t.string :title
          t.text :body
          t.timestamps
          t.string :all_text, :limit => 1 # will be used for multi-column index
        end
      end
      class ::Post < ActiveRecord::Base
        has_context_index
      end
      @post0 = Post.create(:title => "dummy title", :body => "dummy body")
      @post1 = Post.create(:title => @title_words.join(' '), :body => @body_words.join(' '))
      @post2 = Post.create(:title => (@title_words*2).join(' '), :body => (@body_words*2).join(' '))
    end

    after(:all) do
      schema_define { drop_table :posts }
      Object.send(:remove_const, "Post")
    end

    after(:each) do
      @post.destroy if @post
    end

    it "should create single VARCHAR2 column index" do
      @conn.add_context_index :posts, :title
      @title_words.each do |word|
        Post.contains(:title, word).all.should == [@post2, @post1]
      end
      @conn.remove_context_index :posts, :title
    end

    it "should create single CLOB column index" do
      @conn.add_context_index :posts, :body
      @body_words.each do |word|
        Post.contains(:body, word).all.should == [@post2, @post1]
      end
      @conn.remove_context_index :posts, :body
    end

    it "should not include text index secondary tables in user tables list" do
      @conn.add_context_index :posts, :title
      @conn.tables.any?{|t| t =~ /^dr\$/i}.should be_false
      @conn.remove_context_index :posts, :title
    end

    it "should create multiple column index" do
      @conn.add_context_index :posts, [:title, :body]
      (@title_words+@body_words).each do |word|
        Post.contains(:title, word).all.should == [@post2, @post1]
      end
      @conn.remove_context_index :posts, [:title, :body]
    end

    it "should create multiple column index with specified main index column" do
      @conn.add_context_index :posts, [:title, :body],
        :index_column => :all_text, :sync => 'ON COMMIT'
      @post = Post.create(:title => "abc", :body => "def")
      Post.contains(:all_text, "abc").all.should == [@post]
      Post.contains(:all_text, "def").all.should == [@post]
      @post.update_attributes!(:title => "ghi")
      # index will not be updated as all_text column is not changed
      Post.contains(:all_text, "ghi").all.should be_empty
      @post.update_attributes!(:all_text => "1")
      # index will be updated when all_text column is changed
      Post.contains(:all_text, "ghi").all.should == [@post]
      @conn.remove_context_index :posts, :index_column => :all_text
    end

    it "should create multiple column index with trigger updated main index column" do
      @conn.add_context_index :posts, [:title, :body],
        :index_column => :all_text, :index_column_trigger_on => [:created_at, :updated_at],
        :sync => 'ON COMMIT'
      @post = Post.create(:title => "abc", :body => "def")
      Post.contains(:all_text, "abc").all.should == [@post]
      Post.contains(:all_text, "def").all.should == [@post]
      @post.update_attributes!(:title => "ghi")
      # index should be updated as created_at column is changed
      Post.contains(:all_text, "ghi").all.should == [@post]
      @conn.remove_context_index :posts, :index_column => :all_text
    end

  end

  describe "on multiple tables" do
    before(:all) do
      schema_define do
        create_table :posts, :force => true do |t|
          t.string :title
          t.text :body
          t.integer :comments_count
          t.timestamps
          t.string :all_text, :limit => 1 # will be used for multi-column index
        end
        create_table :comments, :force => true do |t|
          t.integer :post_id
          t.string :author
          t.text :body
          t.timestamps
        end
      end
      class ::Post < ActiveRecord::Base
        has_many :comments, :dependent => :destroy
        has_context_index
      end
      class ::Comment < ActiveRecord::Base
        belongs_to :post, :counter_cache => true
      end
    end

    after(:all) do
      schema_define { drop_table :comments; drop_table :posts }
      Object.send(:remove_const, "Comment")
      Object.send(:remove_const, "Post")
    end

    after(:each) do
      Post.destroy_all
    end

    it "should create multiple table index with specified main index column" do
      @conn.add_context_index :posts,
        [:title, :body,
        # specify aliases always with AS keyword
        "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        ],
        :name => 'post_and_comments_index',
        :index_column => :all_text, :index_column_trigger_on => [:updated_at, :comments_count],
        :sync => 'ON COMMIT'
      @post = Post.create!(:title => "aaa", :body => "bbb")
      @post.comments.create!(:author => "ccc", :body => "ddd")
      @post.comments.create!(:author => "eee", :body => "fff")
      ["aaa", "bbb", "ccc", "ddd", "eee", "fff"].each do |word|
        Post.contains(:all_text, word).all.should == [@post]
      end
      @conn.remove_context_index :posts, :name => 'post_and_comments_index'
    end

    it "should find by search term within specified field" do
      @post = Post.create!(:title => "aaa", :body => "bbb")
      @post.comments.create!(:author => "ccc", :body => "ddd")
      @conn.add_context_index :posts,
        [:title, :body,
        # specify aliases always with AS keyword
        "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        ],
        :index_column => :all_text
      Post.contains(:all_text, "aaa within title").all.should == [@post]
      Post.contains(:all_text, "aaa within body").all.should be_empty
      Post.contains(:all_text, "bbb within body").all.should == [@post]
      Post.contains(:all_text, "bbb within title").all.should be_empty
      Post.contains(:all_text, "ccc within comment_author").all.should == [@post]
      Post.contains(:all_text, "ccc within comment_body").all.should be_empty
      Post.contains(:all_text, "ddd within comment_body").all.should == [@post]
      Post.contains(:all_text, "ddd within comment_author").all.should be_empty
      @conn.remove_context_index :posts, :index_column => :all_text
    end

  end

  describe "schema dump" do
    before(:all) do
      schema_define do
        create_table :posts, :force => true do |t|
          t.string :title
          t.text :body
          t.integer :comments_count
          t.timestamps
          t.string :all_text, :limit => 1 # will be used for multi-column index
        end
        create_table :comments, :force => true do |t|
          t.integer :post_id
          t.string :author
          t.text :body
          t.timestamps
        end
      end
    end

    after(:all) do
      schema_define { drop_table :comments; drop_table :posts }
    end

    def standard_dump
      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = []
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
      stream.string
    end

    it "should dump definition of single column index" do
      @conn.add_context_index :posts, :title
      standard_dump.should =~ /add_context_index "posts", \["title"\], :name => \"index_posts_on_title\"$/
      @conn.remove_context_index :posts, :title
    end

    it "should dump definition of multiple column index" do
      @conn.add_context_index :posts, [:title, :body]
      standard_dump.should =~ /add_context_index :posts, \[:title, :body\]$/
      @conn.remove_context_index :posts, [:title, :body]
    end

    it "should dump definition of multiple table index with options" do
      options = {
        :name => 'post_and_comments_index',
        :index_column => :all_text, :index_column_trigger_on => :updated_at,
        :sync => 'ON COMMIT'
      }
      @conn.add_context_index :posts,
        [:title, :body,
        "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        ], options
      standard_dump.should =~ /add_context_index :posts, \[:title, :body, "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"\], #{options.inspect[1..-2]}$/
      @conn.remove_context_index :posts, :name => 'post_and_comments_index'
    end

  end

end