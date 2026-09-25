# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem "activerecord", github: "rails/rails", branch: "8-0-stable"
  gem "activerecord-oracle_enhanced-adapter",  github: "rsim/oracle-enhanced", branch: "release80"
  gem "rspec", require: "rspec/autorun"

  platforms :ruby do
    gem "ruby-oci8", github: "kubo/ruby-oci8"
  end
end

require "active_record"
require "logger"
require "active_record/connection_adapters/oracle_enhanced_adapter"

# Set Oracle enhanced adapter specific connection parameters
DATABASE_NAME = ENV["DATABASE_NAME"] || "orcl"
DATABASE_HOST = ENV["DATABASE_HOST"]
DATABASE_PORT = ENV["DATABASE_PORT"]
DATABASE_USER = ENV["DATABASE_USER"] || "oracle_enhanced"
DATABASE_PASSWORD = ENV["DATABASE_PASSWORD"] || "oracle_enhanced"
DATABASE_SYS_PASSWORD = ENV["DATABASE_SYS_PASSWORD"] || "admin"

CONNECTION_PARAMS = {
  adapter: "oracle_enhanced",
  database: DATABASE_NAME,
  host: DATABASE_HOST,
  port: DATABASE_PORT,
  username: DATABASE_USER,
  password: DATABASE_PASSWORD
}

ActiveRecord::Base.logger = Logger.new(STDOUT)

describe "bug test" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Schema.define do
      create_table :posts, force: true do |t|
      end

      create_table :comments, force: true do |t|
        t.integer :post_id
      end
    end
    class Post < ActiveRecord::Base
      has_many :comments
    end

    class Comment < ActiveRecord::Base
      belongs_to :post
    end
  end

  it "should pass association stuff" do
    post = Post.create!
    post.comments << Comment.create!
    expect(1).to eq(post.comments.count)
    expect(1).to eq(Comment.count)
    expect(post.id).to eq(Comment.first.post.id)
  end
end
