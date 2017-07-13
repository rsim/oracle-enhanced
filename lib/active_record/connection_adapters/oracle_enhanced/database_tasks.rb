# frozen_string_literal: true

require "active_record/base"

module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter
      class DatabaseTasks
        delegate :connection, :establish_connection, to: ActiveRecord::Base

        def initialize(config)
          @config = config
        end

        def create
          system_password = ENV.fetch("ORACLE_SYSTEM_PASSWORD") {
            print "Please provide the SYSTEM password for your Oracle installation (set ORACLE_SYSTEM_PASSWORD to avoid this prompt)\n>"
            $stdin.gets.strip
          }
          establish_connection(@config.merge("username" => "SYSTEM", "password" => system_password))
          begin
            connection.execute "CREATE USER #{@config['username']} IDENTIFIED BY #{@config['password']}"
          rescue => e
            if e.message =~ /ORA-01920/ # user name conflicts with another user or role name
              connection.execute "ALTER USER #{@config['username']} IDENTIFIED BY #{@config['password']}"
            else
              raise e
            end
          end
          connection.execute "GRANT unlimited tablespace TO #{@config['username']}"
          connection.execute "GRANT create session TO #{@config['username']}"
          connection.execute "GRANT create table TO #{@config['username']}"
          connection.execute "GRANT create view TO #{@config['username']}"
          connection.execute "GRANT create sequence TO #{@config['username']}"
        end

        def drop
          establish_connection(@config)
          connection.execute_structure_dump(connection.full_drop)
        end

        def purge
          drop
          connection.execute("PURGE RECYCLEBIN") rescue nil
        end

        def structure_dump(filename, extra_flags)
          establish_connection(@config)
          File.open(filename, "w:utf-8") { |f| f << connection.structure_dump }
          if @config["structure_dump"] == "db_stored_code"
            File.open(filename, "a") { |f| f << connection.structure_dump_db_stored_code }
          end
        end

        def structure_load(filename, extra_flags)
          establish_connection(@config)
          connection.execute_structure_dump(File.read(filename))
        end
      end
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.register_task(/(oci|oracle)/, ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::DatabaseTasks)
