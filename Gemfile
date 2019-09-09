# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rdoc"
  gem "rake", "~> 13.0.0.pre.1"
  gem "rubocop", "~> 0.74.0", require: false
  gem "rubocop-performance", "~> 1.3.0", require: false
  gem "rubocop-rails", "~> 2.0.0", require: false

  gem "activerecord",   github: "rails/rails", branch: "master"
  gem "ruby-plsql", github: "rsim/ruby-plsql", branch: "master"

  platforms :ruby do
    gem "ruby-oci8",    github: "kubo/ruby-oci8"
    gem "byebug"
  end

  platforms :jruby do
    gem "pry"
    gem "pry-nav"
  end
end

group :test do
  gem "simplecov",  github: "colszowka/simplecov", branch: "master", require: false
end
