# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rdoc"
  gem "rake"
  gem "rubocop", "~> 0.67.0", require: false
  gem "rubocop-performance", require: false

  gem "activerecord",   github: "rails/rails", branch: "6-0-stable"
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
