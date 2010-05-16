# RSI: implementation idea taken from JDBC adapter
def redefine_task(*args, &block)
  task_name = Hash === args.first ? args.first.keys[0] : args.first
  existing_task = Rake.application.lookup task_name
  if existing_task
    class << existing_task; public :instance_variable_set; end
    existing_task.instance_variable_set "@prerequisites", FileList[]
    existing_task.instance_variable_set "@actions", []
  end
  task(*args, &block)
end

namespace :db do

  namespace :structure do
    redefine_task :dump => :environment do
      abcs = ActiveRecord::Base.configurations
      rails_env = defined?(Rails.env) ? Rails.env : RAILS_ENV
      ActiveRecord::Base.establish_connection(abcs[rails_env])
      File.open("db/#{rails_env}_structure.sql", "w+") { |f| f << ActiveRecord::Base.connection.structure_dump }
      if ActiveRecord::Base.connection.supports_migrations?
        File.open("db/#{rails_env}_structure.sql", "a") { |f| f << ActiveRecord::Base.connection.dump_schema_information }
      end
      if abcs[rails_env]['structure_dump'] == "db_stored_code"
         File.open("db/#{rails_env}_structure.sql", "a") { |f| f << ActiveRecord::Base.connection.structure_dump_db_stored_code }
      end

    end
  end

  namespace :test do
    redefine_task :clone_structure => [ "db:structure:dump", "db:test:purge" ] do
      abcs = ActiveRecord::Base.configurations
      rails_env = defined?(Rails.env) ? Rails.env : RAILS_ENV
      ActiveRecord::Base.establish_connection(:test)
      File.read("db/#{rails_env}_structure.sql").
            split(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::STATEMENT_TOKEN).each do |ddl|
        ddl.chop! if ddl.last == ";"
        ActiveRecord::Base.connection.execute(ddl) unless ddl.blank?
      end
    end

    redefine_task :purge => :environment do
      abcs = ActiveRecord::Base.configurations
      ActiveRecord::Base.establish_connection(:test)
      ActiveRecord::Base.connection.full_drop.
            split(ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::STATEMENT_TOKEN).each do |ddl|
        ddl.chop! if ddl.last == ";"
        ActiveRecord::Base.connection.execute(ddl) unless ddl.blank?
      end
    end

  end
end
