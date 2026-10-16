# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rdoc"
  gem "rake"
  gem "activerecord",   github: "rails/rails", branch: "7-0-stable"
  gem "ruby-plsql", github: "rsim/ruby-plsql", branch: "master"
  # Rails 7.0 passes the quirks_mode option to JSON.generate, which json 3.0 removed
  gem "json", "< 3"

  platforms :ruby do
    gem "ruby-oci8",    github: "kubo/ruby-oci8"
    gem "byebug"
  end

  platforms :jruby do
    gem "pry"
    gem "pry-nav"
  end
end

group :rubocop do
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
end
