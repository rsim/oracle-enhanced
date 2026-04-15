# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      # Formats +schema_migrations+ versions into an Oracle-flavored INSERT
      # block for +structure.sql+ dumps.
      #
      # Mirrors the pluggable API introduced in rails/rails#53797
      # (ActiveRecord::Migration::DefaultSchemaVersionsFormatter), but emits
      # +INSERT ALL ... SELECT * FROM DUAL+ because Oracle < 23c does not
      # support the standard multi-row +VALUES+ syntax the default formatter
      # uses.
      #
      # Versions are dumped newest-first (rails/rails#44363), so a newly
      # added migration appears at the top of the INSERT ALL block. The
      # merge-conflict rationale behind 44363 is specific to the default
      # formatter's VALUES list (semicolon/comma shuffle on the last line);
      # Oracle's INSERT ALL has no such coupling between adjacent lines,
      # but we keep the same order to stay consistent with structure.sql
      # from the other Rails adapters.
      class SchemaVersionsFormatter
        def initialize(connection)
          @connection = connection
        end

        def format(versions)
          sm_table = connection.quote_table_name(connection.pool.schema_migration.table_name)

          if versions.is_a?(Array)
            if connection.supports_multi_insert?
              versions.reverse.inject(+"INSERT ALL\n") { |sql, version|
                sql << "INTO #{sm_table} (version) VALUES (#{connection.quote(version)})\n"
              } << "SELECT * FROM DUAL\n"
            else
              versions.reverse.map { |version|
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
