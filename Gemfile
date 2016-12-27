source "http://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

group :development do
  gem "rspec"
  gem "rdoc"
  gem "rake"

  gem "activerecord",   github: "rails/rails", branch: "master"
  gem "rack",           github: "rack/rack", branch: "master"
  gem "arel",           github: "rails/arel", branch: "7-1-stable"

  gem "ruby-plsql", ">=0.5.0"

  platforms :ruby do
    gem "ruby-oci8",    github: "kubo/ruby-oci8"
    gem "byebug"
  end

  platforms :jruby do
    gem "ruby-debug"
    gem "pry"
    gem "pry-nav"
  end
end

group :test do
  gem "simplecov",  github: "colszowka/simplecov", branch: "master", require: false
end
