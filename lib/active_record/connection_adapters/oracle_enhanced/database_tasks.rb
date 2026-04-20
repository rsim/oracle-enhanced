# frozen_string_literal: true

require "active_record/base"
require "active_record/tasks/abstract_tasks"

module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter
      class DatabaseTasks < ActiveRecord::Tasks::AbstractTasks
        def create
          system_password = ENV.fetch("ORACLE_SYSTEM_PASSWORD") {
            print "Please provide the SYSTEM password for your Oracle installation (set ORACLE_SYSTEM_PASSWORD to avoid this prompt)\n>"
            $stdin.gets.strip
          }
          establish_connection(configuration_hash.merge(username: "SYSTEM", password: system_password))
          begin
            connection.execute "CREATE USER #{configuration_hash[:username]} IDENTIFIED BY #{configuration_hash[:password]}"
          rescue => e
            if /ORA-01920/.match?(e.message) # user name conflicts with another user or role name
              connection.execute "ALTER USER #{configuration_hash[:username]} IDENTIFIED BY #{configuration_hash[:password]}"
            else
              raise e
            end
          end

          OracleEnhancedAdapter.permissions.each do |permission|
            connection.execute "GRANT #{permission} TO #{configuration_hash[:username]}"
          end
        end

        def drop
          establish_connection
          connection.execute_structure_dump(connection.full_drop)
        end

        def purge
          drop
          connection.execute("PURGE RECYCLEBIN") rescue nil
        end

        def structure_dump(filename, extra_flags)
          establish_connection
          File.open(filename, "w:utf-8") { |f| f << connection.structure_dump }
          if configuration_hash[:structure_dump] == "db_stored_code"
            File.open(filename, "a:utf-8") { |f| f << connection.structure_dump_db_stored_code }
          end
        end

        def structure_load(filename, extra_flags)
          establish_connection
          connection.execute_structure_dump(File.read(filename))
        end
      end
    end
  end
end

ActiveRecord::Tasks::DatabaseTasks.register_task(/(oci|oracle)/, ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter::DatabaseTasks)
