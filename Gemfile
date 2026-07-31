# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rake"
  # rails/rails@96afb7e4 = merge of rails/rails#58297 (deprecate positional
  # pk/id_value/sequence_name for #insert); bump per follow-up Rails change
  gem "activerecord",   github: "rails/rails", ref: "96afb7e44a030940e4868de65dcc48739b1d2f20"
  gem "ruby-plsql", github: "rsim/ruby-plsql", branch: "master"

  platforms :ruby do
    gem "ruby-oci8",    github: "kubo/ruby-oci8"
    gem "rdoc"
    gem "debug", require: false
  end

  platforms :jruby do
    gem "pry"
    gem "pry-nav"
  end
end

group :rubocop do
  gem "rubocop", "!= 1.84.0", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
end
