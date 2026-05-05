# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      class SchemaVersionsFormatter
        def initialize(connection)
          @connection = connection
        end

        def format(versions)
          sm_table = connection.quote_table_name(connection.pool.schema_migration.table_name)

          if versions.is_a?(Array)
            if connection.database_version >= "11.2"
              versions.inject(+"INSERT ALL\n") { |sql, version|
                sql << "INTO #{sm_table} (version) VALUES (#{connection.quote(version)})\n"
              } << "SELECT * FROM DUAL\n"
            else
              versions.map { |version|
                "INSERT INTO #{sm_table} (version) VALUES (#{connection.quote(version)})"
              }.join("\n\n/\n\n")
            end
          else
            "INSERT INTO #{sm_table} (version) VALUES (#{connection.quote(versions)})"
          end
        end

        private
          attr_reader :connection
      end
    end
  end
end
