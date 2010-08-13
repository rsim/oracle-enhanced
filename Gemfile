source 'http://rubygems.org'

gem 'jeweler'
gem 'rspec', "~> 1.3.0"

if ENV['RAILS_GEM_VERSION']
  gem 'activerecord', "=#{ENV['RAILS_GEM_VERSION']}"
  gem 'actionpack', "=#{ENV['RAILS_GEM_VERSION']}"
  gem 'activesupport', "=#{ENV['RAILS_GEM_VERSION']}"
  case ENV['RAILS_GEM_VERSION']
  when /^2.0/
    gem 'composite_primary_keys', '=0.9.93'
  when /^2.1/
    gem 'composite_primary_keys', '=1.0.8'
  when /^2.2/
    gem 'composite_primary_keys', '=2.2.2'
  when /^2.3.3/
    gem 'composite_primary_keys', '=2.3.2'
  when /^3/
    gem 'railties', "=#{ENV['RAILS_GEM_VERSION']}"
  end
else
  # uses local copy of Rails 3 and Arel gems
  ENV['RAILS_GEM_PATH'] ||= '../rails'
  %w(activerecord activemodel activesupport actionpack railties).each do |gem_name|
    gem gem_name, :path => File.join(ENV['RAILS_GEM_PATH'], gem_name)
  end

  ENV['AREL_GEM_PATH'] ||= '../arel'
  gem 'arel', :path => ENV['AREL_GEM_PATH']
end

if !defined?(RUBY_ENGINE) || RUBY_ENGINE == 'ruby'
  gem 'ruby-oci8', '>=2.0.4'
elsif RUBY_ENGINE == 'jruby'
  gem 'activerecord-jdbc-adapter'
end

gem 'ruby-plsql', '>=0.4.3'
