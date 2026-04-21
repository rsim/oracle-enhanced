# frozen_string_literal: true

require "active_record/base"
require "active_record/tasks/abstract_tasks"

module ActiveRecord
  module ConnectionAdapters
    class OracleEnhancedAdapter
      class DatabaseTasks < ActiveRecord::Tasks::AbstractTasks
        ORACLE_IDENTIFIER = /\A[[:alpha:]][\w$#]*\z/
        # GRANT operand: one or more space-separated tokens consisting of
        # word chars only. Covers system privileges (e.g. "create session",
        # "CREATE ANY TABLE") and simple role names. Rejects separators such
        # as `;`, `--`, `'`, `"`, as well as newlines/tabs — anything that
        # could turn a single GRANT into multiple statements or otherwise
        # make the operand hard to reason about.
        ORACLE_PRIVILEGE = /\A\w+( \w+)*\z/

        def create
          username = configuration_hash[:username].to_s
          unless username.match?(ORACLE_IDENTIFIER)
            raise ArgumentError, "Invalid Oracle identifier for :username: #{username.inspect}"
          end
          OracleEnhancedAdapter.permissions.each do |permission|
            unless permission.to_s.match?(ORACLE_PRIVILEGE)
              raise ArgumentError, "Invalid Oracle privilege in OracleEnhancedAdapter.permissions: #{permission.inspect}"
            end
          end
          # Oracle Autonomous Database (OCI) ships with ADMIN -- not SYSTEM --
          # as the predefined administrative user, so the caller needs a way
          # to override the default. See
          # https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/autonomous-admin-user-roles.html
          system_username = ENV["ORACLE_SYSTEM_USER"].presence || "SYSTEM"
          unless system_username.match?(ORACLE_IDENTIFIER)
            raise ArgumentError, "Invalid Oracle identifier for ORACLE_SYSTEM_USER: #{system_username.inspect}"
          end
          quoted_password = %("#{configuration_hash[:password].to_s.gsub('"', '""')}")

          system_password = ENV.fetch("ORACLE_SYSTEM_PASSWORD") {
            print "Please provide the #{system_username} password for your Oracle installation (set ORACLE_SYSTEM_PASSWORD to avoid this prompt)\n>"
            $stdin.gets.strip
          }
          establish_connection(configuration_hash.merge(username: system_username, password: system_password))
          begin
            connection.execute "CREATE USER #{username} IDENTIFIED BY #{quoted_password}"
          rescue => e
            if e.message.include?("ORA-01920") # user name conflicts with another user or role name
              connection.execute "ALTER USER #{username} IDENTIFIED BY #{quoted_password}"
            else
              raise e
            end
          end

          OracleEnhancedAdapter.permissions.each do |permission|
            connection.execute "GRANT #{permission} TO #{username}"
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
