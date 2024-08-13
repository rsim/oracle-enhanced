# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

group :development do
  gem "rspec"
  gem "rdoc"
  gem "rake"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false

  #  gem "activerecord",   github: "rails/rails", ref: "3421e892afa532a254e54379ac2ce9bef138cf3f" # introduction of RETURNING code
  #  gem "activerecord",   github: "rails/rails", ref: "c2c861f98ae25d0daa177898db48f12de1065cf6" # fix for RETURNING code on main (7.2.x)
  #  gem "activerecord",   github: "rails/rails", ref: "221e609ee8cb1dfb686e43481f3e9496b549e974" # backport of RETURNING code to 7-1-stable
  gem "activerecord",   github: "rails/rails", branch: "7-1-stable"
  gem "ruby-plsql", github: "rsim/ruby-plsql", branch: "master"

  platforms :ruby do
    gem "ruby-oci8",    github: "kubo/ruby-oci8"
    gem "debug", require: false
  end

  platforms :jruby do
    gem "pry"
    gem "pry-nav"
  end
end
