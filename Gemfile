source 'http://rubygems.org'

group :development do
  gem 'jeweler', '~> 1.8'
  gem 'rspec', '~> 2.4'
  gem 'rdoc'

  if ENV['RAILS_GEM_VERSION']
    gem 'activerecord', "=#{ENV['RAILS_GEM_VERSION']}"
    gem 'actionpack', "=#{ENV['RAILS_GEM_VERSION']}"
    gem 'activesupport', "=#{ENV['RAILS_GEM_VERSION']}"
    gem 'railties', "=#{ENV['RAILS_GEM_VERSION']}"
  else
    %w(activerecord activemodel activesupport actionpack railties).each do |gem_name|
      if ENV['RAILS_GEM_PATH']
        gem gem_name, :path => File.join(ENV['RAILS_GEM_PATH'], gem_name)
      else
        gem gem_name, :git => "git://github.com/rails/rails"
      end
    end

    if ENV['AREL_GEM_PATH']
      gem 'arel', :path => ENV['AREL_GEM_PATH']
    else
      gem 'arel', :git => "git://github.com/rails/arel"
    end

    if ENV['JOURNEY_GEM_PATH']
      gem 'journey', :path => ENV['JOURNEY_GEM_PATH']
    else
      gem "journey", :git => "git://github.com/rails/journey"
    end
  end

  gem "activerecord-deprecated_finders"
  gem 'ruby-plsql', '>=0.5.0'

  platforms :ruby do
    gem 'ruby-oci8', '>=2.1.2'
  end

end
