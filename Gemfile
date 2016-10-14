source 'http://rubygems.org'

group :development do
  gem 'rspec', '~> 3.3'
  gem 'rdoc', '~> 5.0.0.beta2'
  gem 'rake'

  gem 'activerecord',   github: 'rails/rails', branch: '5-0-stable'
  gem 'rack',           github: 'rack/rack', branch: 'master'
  gem 'arel',           github: 'rails/arel', branch: '7-1-stable'

  gem 'ruby-plsql', '>=0.5.0'

  platforms :ruby do
    gem 'ruby-oci8',    github: 'kubo/ruby-oci8'
    gem 'byebug'
  end

  platforms :jruby do
    gem 'ruby-debug'
  end
end
