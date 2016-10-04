begin
  require 'bundler/inline'
rescue LoadError => e
  $stderr.puts 'Bundler version 1.10 or later is required. Please update your Bundler'
  raise e
end

gemfile(true) do
  source 'https://rubygems.org'
  gem 'rails', '~> 5.0.0'
  gem 'activerecord-oracle_enhanced-adapter', '~> 1.7.0'
  gem 'ruby-oci8'
  gem 'rspec'
end

require 'active_record'
require 'rspec'
require 'logger'
require 'active_record/connection_adapters/oracle_enhanced_adapter'

# Set Oracle enhanced adapter specific connection parameters
DATABASE_NAME = ENV['DATABASE_NAME'] || 'orcl'
DATABASE_HOST = ENV['DATABASE_HOST']
DATABASE_PORT = ENV['DATABASE_PORT']
DATABASE_USER = ENV['DATABASE_USER'] || 'oracle_enhanced'
DATABASE_PASSWORD = ENV['DATABASE_PASSWORD'] || 'oracle_enhanced'
DATABASE_SYS_PASSWORD = ENV['DATABASE_SYS_PASSWORD'] || 'admin'

CONNECTION_PARAMS = {
  :adapter => "oracle_enhanced",
  :database => DATABASE_NAME,
  :host => DATABASE_HOST,
  :port => DATABASE_PORT,
  :username => DATABASE_USER,
  :password => DATABASE_PASSWORD
}


ActiveRecord::Base.logger = Logger.new(STDOUT)

describe "bug test" do
  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    ActiveRecord::Schema.define do
      create_table :posts, :force => true do |t|
      end

      create_table :comments, :force => true do |t|
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
