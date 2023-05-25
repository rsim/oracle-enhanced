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

<<<<<<< HEAD
  gem "activerecord",   github: "rails/rails", ref: "0e9267767f19065fa513038253179ad6b05c29ab"
=======
  gem "activerecord",   github: "rails/rails", ref: "deec3004d8d85443dc4f3f5fd22ab86b10adb58b"
>>>>>>> de98281a (Support `Configure legacy-API-supplied connection before first use`)
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
