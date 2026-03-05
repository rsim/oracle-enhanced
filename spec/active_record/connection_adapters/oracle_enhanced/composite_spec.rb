# frozen_string_literal: true

describe "OracleEnhancedAdapter should support composite primary" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    schema_define do
      create_table :test_authors, force: true do |t|
        t.string    :first_name,    limit: 20
        t.string    :last_name,     limit: 25
      end

      create_table :test_books, force: true do |t|
        t.string    :title,       limit: 20
      end

      create_table :test_authors_test_books, primary_key: ["test_author_id", "test_book_id"], force: true do |t|
        t.integer "test_author_id", precision: 38, null: false
        t.integer "test_book_id", precision: 38, null: false
      end
    end
  end

  after(:all) do
    schema_define do
      drop_table :test_authors
      drop_table :test_books
      drop_table :test_authors_test_books
    end
  end

  before(:each) do
    class ::TestAuthor < ActiveRecord::Base
      has_many :test_authors_test_books
      has_many :test_books, through: :test_authors_test_books, inverse_of: :test_authors
    end
    class ::TestBook < ActiveRecord::Base
      has_many :test_authors_test_books
      has_many :test_authors, through: :test_authors_test_books, inverse_of: :test_books
    end
    class ::TestAuthorsTestBook < ActiveRecord::Base
      self.primary_key = [:test_author_id, :test_book_id]
      belongs_to :test_author, foreign_key: :test_author_id
      belongs_to :test_book, foreign_key: :test_book_id
    end

    @author = TestAuthor.create!(
      first_name: "First",
      last_name: "Last",
    )
    @book = TestBook.create!(title: "Nice book")
    @testRel = TestAuthorsTestBook.create!(test_author: @author, test_book: @book)
    expect([@book]).to eq(@author.test_books)
  end

  after(:each) do
    TestAuthor.delete_all
    TestBook.delete_all
    TestAuthorsTestBook.delete_all
    Object.send(:remove_const, "TestAuthor")
    Object.send(:remove_const, "TestBook")
    Object.send(:remove_const, "TestAuthorsTestBook")
    ActiveRecord::Base.clear_cache!
  end

  it "should support distinct" do
    TestAuthor.distinct.count.should == 1
    skip "this appears to be a rails bug https://github.com/rails/rails/issues/55401"
    TestAuthorsTestBook.distinct.count.should == 1
  end

  it "should support includes when requesting the first record by a referenced composite idx association" do
    expect([@book]).to eq(@author.test_books)
    expect(TestAuthor.includes(:test_authors_test_books).references(:test_authors_test_books).merge(TestAuthorsTestBook.where(test_author: @author)).take).to eq(@author)
    expect(TestAuthor.includes(:test_authors_test_books).references(:test_authors_test_books).merge(TestAuthorsTestBook.where(test_author: @author)).first).to eq(@author)
  end

  it "should support includes when requesting the first record by a referenced association" do
    expect([@book]).to eq(@author.test_books)
    expect(TestAuthorsTestBook.includes(:test_author).references(:test_author).merge(TestAuthor.where(first_name: "First")).take).to eq(@testRel)
    expect(TestAuthorsTestBook.includes(:test_author).references(:test_author).merge(TestAuthor.where(first_name: "First")).first).to eq(@testRel)
  end
end
