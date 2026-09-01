# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rake"
  # rails/rails@342dafc5 = merge of rails/rails#58239 (CommandRecorder stores
  # args and kwargs separately); bump per follow-up Rails change
  gem "activerecord",   github: "rails/rails", ref: "342dafc5351d9c9e303ee3c1e378c4dcf2277ffd"
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
