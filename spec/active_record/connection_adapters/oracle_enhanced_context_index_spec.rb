require 'spec_helper'

describe "OracleEnhancedAdapter context index" do
  include SchemaSpecHelper
  include LoggerSpecHelper

  def create_table_posts
    schema_define do
      create_table :posts, force: true do |t|
        t.string :title
        t.text :body
        t.integer :comments_count
        t.timestamps null: true
        t.string :all_text, limit: 2 # will be used for multi-column index
      end
    end
  end

  def create_table_comments
    schema_define do
      create_table :comments, force: true do |t|
        t.integer :post_id
        t.string :author
        t.text :body
        t.timestamps null: true
      end
    end
  end

  def create_tables
    create_table_posts
    create_table_comments
  end

  def drop_table_posts
    schema_define { drop_table :posts }
  end

  def drop_table_comments
    schema_define { drop_table :comments }
  end

  def drop_tables
    drop_table_comments
    drop_table_posts
  end

  # Try to grant CTXAPP role to be able to set CONTEXT index parameters.
  def grant_ctxapp
    @sys_conn = ActiveRecord::ConnectionAdapters::OracleEnhancedConnection.create(SYS_CONNECTION_PARAMS)
    @sys_conn.exec "GRANT CTXAPP TO #{DATABASE_USER}"
  rescue
    nil
  end

  before(:all) do
    grant_ctxapp
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
  end

  describe "on single table" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      @title_words = %w{aaa bbb ccc}
      @body_words = %w{foo bar baz}
      create_table_posts
      class ::Post < ActiveRecord::Base
        has_context_index
      end
      @post0 = Post.create(title: "dummy title", body: "dummy body")
      @post1 = Post.create(title: @title_words.join(' '), body: @body_words.join(' '))
      @post2 = Post.create(title: (@title_words*2).join(' '), body: (@body_words*2).join(' '))
      @post_with_null_body = Post.create(title: "withnull", body: nil)
      @post_with_null_title = Post.create(title: nil, body: "withnull")
    end

    after(:all) do
      drop_table_posts
      Object.send(:remove_const, "Post")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    after(:each) do
      @post.destroy if @post
    end

    it "should create single VARCHAR2 column index" do
      @conn.add_context_index :posts, :title
      @title_words.each do |word|
        expect(Post.contains(:title, word).to_a).to eq([@post2, @post1])
      end
      @conn.remove_context_index :posts, :title
    end

    it "should create single CLOB column index" do
      @conn.add_context_index :posts, :body
      @body_words.each do |word|
        expect(Post.contains(:body, word).to_a).to eq([@post2, @post1])
      end
      @conn.remove_context_index :posts, :body
    end

    it "should not include text index secondary tables in user tables list" do
      @conn.add_context_index :posts, :title
      expect(@conn.tables.any?{|t| t =~ /^dr\$/i}).to be_falsey
      @conn.remove_context_index :posts, :title
    end

    it "should create multiple column index" do
      @conn.add_context_index :posts, [:title, :body]
      (@title_words+@body_words).each do |word|
        expect(Post.contains(:title, word).to_a).to eq([@post2, @post1])
      end
      @conn.remove_context_index :posts, [:title, :body]
    end

    it "should index records with null values" do
      @conn.add_context_index :posts, [:title, :body]
      expect(Post.contains(:title, "withnull").to_a).to eq([@post_with_null_body, @post_with_null_title])
      @conn.remove_context_index :posts, [:title, :body]
    end

    it "should create multiple column index with specified main index column" do
      @conn.add_context_index :posts, [:title, :body],
        index_column: :all_text, sync: 'ON COMMIT'
      @post = Post.create(title: "abc", body: "def")
      expect(Post.contains(:all_text, "abc").to_a).to eq([@post])
      expect(Post.contains(:all_text, "def").to_a).to eq([@post])
      @post.update_attributes!(title: "ghi")
      # index will not be updated as all_text column is not changed
      expect(Post.contains(:all_text, "ghi").to_a).to be_empty
      @post.update_attributes!(all_text: "1")
      # index will be updated when all_text column is changed
      expect(Post.contains(:all_text, "ghi").to_a).to eq([@post])
      @conn.remove_context_index :posts, index_column: :all_text
    end

    it "should create multiple column index with trigger updated main index column" do
      @conn.add_context_index :posts, [:title, :body],
        index_column: :all_text, index_column_trigger_on: [:created_at, :updated_at],
        sync: 'ON COMMIT'
      @post = Post.create(title: "abc", body: "def")
      expect(Post.contains(:all_text, "abc").to_a).to eq([@post])
      expect(Post.contains(:all_text, "def").to_a).to eq([@post])
      @post.update_attributes!(title: "ghi")
      # index should be updated as created_at column is changed
      expect(Post.contains(:all_text, "ghi").to_a).to eq([@post])
      @conn.remove_context_index :posts, index_column: :all_text
    end

    it "should use base letter conversion with BASIC_LEXER" do
      @post = Post.create!(title: "āčē", body: "dummy")
      @conn.add_context_index :posts, :title,
        lexer: { type: "BASIC_LEXER", base_letter_type: 'GENERIC', base_letter: true }
      expect(Post.contains(:title, "āčē").to_a).to eq([@post])
      expect(Post.contains(:title, "ace").to_a).to eq([@post])
      expect(Post.contains(:title, "ACE").to_a).to eq([@post])
      @conn.remove_context_index :posts, :title
    end

    it "should create transactional index and sync index within transaction on inserts and updates" do
      @conn.add_context_index :posts, :title, transactional: true
      Post.transaction do
        @post = Post.create(title: "abc")
        expect(Post.contains(:title, "abc").to_a).to eq([@post])
        @post.update_attributes!(title: "ghi")
        expect(Post.contains(:title, "ghi").to_a).to eq([@post])
      end
      @conn.remove_context_index :posts, :title
    end

    it "should use index when contains has schema_name.table_name syntax" do
      @conn.add_context_index :posts, :title
      @title_words.each do |word|
        Post.contains('posts.title', word).to_a.should == [@post2, @post1]
      end
      @conn.remove_context_index :posts, :title
    end
  end

  describe "on multiple tables" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      create_tables
      class ::Post < ActiveRecord::Base
        has_many :comments, dependent: :destroy
        has_context_index
      end
      class ::Comment < ActiveRecord::Base
        belongs_to :post, counter_cache: true
      end
    end

    after(:all) do
      drop_tables
      Object.send(:remove_const, "Comment")
      Object.send(:remove_const, "Post")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    after(:each) do
      @conn.remove_context_index :posts, name: 'post_and_comments_index' rescue nil
      @conn.remove_context_index :posts, index_column: :all_text rescue nil
      Post.destroy_all
    end

    it "should create multiple table index with specified main index column" do
      @conn.add_context_index :posts,
        [:title, :body,
        # specify aliases always with AS keyword
        "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        ],
        name: 'post_and_comments_index',
        index_column: :all_text, index_column_trigger_on: [:updated_at, :comments_count],
        sync: 'ON COMMIT'
      @post = Post.create!(title: "aaa", body: "bbb")
      @post.comments.create!(author: "ccc", body: "ddd")
      @post.comments.create!(author: "eee", body: "fff")
      ["aaa", "bbb", "ccc", "ddd", "eee", "fff"].each do |word|
        expect(Post.contains(:all_text, word).to_a).to eq([@post])
      end
    end

    it "should create multiple table index with specified main index column (when subquery has newlines)" do
      @conn.add_context_index :posts,
        [:title, :body,
         # specify aliases always with AS keyword
         %{ SELECT
             comments.author AS comment_author,
             comments.body AS comment_body
            FROM comments
            WHERE comments.post_id = :id }
        ],
        name: 'post_and_comments_index',
        index_column: :all_text, index_column_trigger_on: [:updated_at, :comments_count],
        sync: 'ON COMMIT'
      @post = Post.create!(title: "aaa", body: "bbb")
      @post.comments.create!(author: "ccc", body: "ddd")
      @post.comments.create!(author: "eee", body: "fff")
      ["aaa", "bbb", "ccc", "ddd", "eee", "fff"].each do |word|
        expect(Post.contains(:all_text, word).to_a).to eq([@post])
      end
    end

    it "should find by search term within specified field" do
      @post = Post.create!(title: "aaa", body: "bbb")
      @post.comments.create!(author: "ccc", body: "ddd")
      @conn.add_context_index :posts,
        [:title, :body,
        # specify aliases always with AS keyword
        "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        ],
        index_column: :all_text
      expect(Post.contains(:all_text, "aaa within title").to_a).to eq([@post])
      expect(Post.contains(:all_text, "aaa within body").to_a).to be_empty
      expect(Post.contains(:all_text, "bbb within body").to_a).to eq([@post])
      expect(Post.contains(:all_text, "bbb within title").to_a).to be_empty
      expect(Post.contains(:all_text, "ccc within comment_author").to_a).to eq([@post])
      expect(Post.contains(:all_text, "ccc within comment_body").to_a).to be_empty
      expect(Post.contains(:all_text, "ddd within comment_body").to_a).to eq([@post])
      expect(Post.contains(:all_text, "ddd within comment_author").to_a).to be_empty
    end

  end

  describe "with specified tablespace" do
    before(:all) do
      @conn = ActiveRecord::Base.connection
      create_table_posts
      class ::Post < ActiveRecord::Base
        has_context_index
      end
      @post = Post.create(title: 'aaa', body: 'bbb')
      @tablespace = @conn.default_tablespace
      set_logger
      @conn = ActiveRecord::Base.connection
    end

    after(:all) do
      drop_table_posts
      Object.send(:remove_const, "Post")
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:"clear_cache!")
    end

    after(:each) do
      clear_logger
    end

    def verify_logged_statements
      ['K_TABLE_CLAUSE', 'R_TABLE_CLAUSE', 'N_TABLE_CLAUSE', 'I_INDEX_CLAUSE', 'P_TABLE_CLAUSE'].each do |clause|
        expect(@logger.output(:debug)).to match(/CTX_DDL\.SET_ATTRIBUTE\('index_posts_on_title_sto', '#{clause}', '.*TABLESPACE #{@tablespace}'\)/)
      end
      expect(@logger.output(:debug)).to match(/CREATE INDEX .* PARAMETERS \('STORAGE index_posts_on_title_sto'\)/)
    end

    it "should create index on single column" do
      @conn.add_context_index :posts, :title, tablespace: @tablespace
      verify_logged_statements
      expect(Post.contains(:title, 'aaa').to_a).to eq([@post])
      @conn.remove_context_index :posts, :title
    end

    it "should create index on multiple columns" do
      @conn.add_context_index :posts, [:title, :body], name: 'index_posts_text', tablespace: @conn.default_tablespace
      verify_logged_statements
      expect(Post.contains(:title, 'aaa AND bbb').to_a).to eq([@post])
      @conn.remove_context_index :posts, name: 'index_posts_text'
    end

  end

  describe "schema dump" do

    def standard_dump
      stream = StringIO.new
      ActiveRecord::SchemaDumper.ignore_tables = []
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
      stream.string
    end

    describe "without table prefixe and suffix" do

      before(:all) do
        @conn = ActiveRecord::Base.connection
        create_tables
      end

      after(:all) do
        drop_tables
      end

      it "should dump definition of single column index" do
        @conn.add_context_index :posts, :title
        expect(standard_dump).to match(/add_context_index "posts", \["title"\], name: \"index_posts_on_title\"$/)
        @conn.remove_context_index :posts, :title
      end

      it "should dump definition of multiple column index" do
        @conn.add_context_index :posts, [:title, :body]
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body\]$/)
        @conn.remove_context_index :posts, [:title, :body]
      end

      it "should dump definition of multiple table index with options" do
        options = {
          name: 'post_and_comments_index',
          index_column: :all_text, index_column_trigger_on: :updated_at,
          transactional: true,
          sync: 'ON COMMIT'
        }
        sub_query = "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
        @conn.add_context_index :posts, [:title, :body, sub_query], options
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body, "#{sub_query}"\], #{options.inspect[1..-2]}$/)
        @conn.remove_context_index :posts, name: 'post_and_comments_index'
      end

      it "should dump definition of multiple table index with options (when definition is larger than 4000 bytes)" do
        options = {
          name: 'post_and_comments_index',
          index_column: :all_text, index_column_trigger_on: :updated_at,
          transactional: true,
          sync: 'ON COMMIT'
        }
        sub_query = "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id#{' AND 1=1' * 500}"
        @conn.add_context_index :posts, [:title, :body, sub_query], options
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body, "#{sub_query}"\], #{options.inspect[1..-2]}$/)
        @conn.remove_context_index :posts, name: 'post_and_comments_index'
      end

      it "should dump definition of multiple table index with options (when subquery has newlines)" do
        options = {
          name: 'post_and_comments_index',
          index_column: :all_text, index_column_trigger_on: :updated_at,
          transactional: true,
          sync: 'ON COMMIT'
        }
        sub_query = "SELECT comments.author AS comment_author, comments.body AS comment_body\nFROM comments\nWHERE comments.post_id = :id"
        @conn.add_context_index :posts, [:title, :body, sub_query], options
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body, "#{sub_query.gsub(/\n/, ' ')}"\], #{options.inspect[1..-2]}$/)
        @conn.remove_context_index :posts, name: 'post_and_comments_index'
      end

    end

    describe "with table prefix and suffix" do
      before(:all) do
        ActiveRecord::Base.table_name_prefix = 'xxx_'
        ActiveRecord::Base.table_name_suffix = '_xxx'
        create_tables
      end

      after(:all) do
        drop_tables
        ActiveRecord::Base.table_name_prefix = ''
        ActiveRecord::Base.table_name_suffix = ''
      end

      it "should dump definition of single column index" do
        schema_define { add_context_index :posts, :title }
        expect(standard_dump).to match(/add_context_index "posts", \["title"\], name: "i_xxx_posts_xxx_title"$/)
        schema_define { remove_context_index :posts, :title }
      end

      it "should dump definition of multiple column index" do
        schema_define { add_context_index :posts, [:title, :body] }
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body\]$/)
        schema_define { remove_context_index :posts, [:title, :body] }
      end

      it "should dump definition of multiple table index with options" do
        options = {
          name: 'xxx_post_and_comments_i',
          index_column: :all_text, index_column_trigger_on: :updated_at,
          lexer: { type: "BASIC_LEXER", base_letter_type: 'GENERIC', base_letter: true },
          wordlist: { type: "BASIC_WORDLIST", prefix_index: true },
          sync: 'ON COMMIT'
        }
        schema_define do
          add_context_index :posts,
            [:title, :body,
            "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
            ], options
        end
        expect(standard_dump).to match(/add_context_index "posts", \[:title, :body, "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"\], #{
          options.inspect[1..-2].gsub(/[{}]/){|s| '\\'<<s }}$/)
        schema_define { remove_context_index :posts, name: 'xxx_post_and_comments_i' }
      end

    end

  end

end
