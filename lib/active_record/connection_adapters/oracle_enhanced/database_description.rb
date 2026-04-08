# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module DatabaseDescription # :nodoc:
        # Used always by JDBC connection as well by OCI connection when describing tables over database link
        def describe(name)
          name = name.to_s
          if name.include?("@")
            raise ArgumentError "db link is not supported"
          else
            default_owner = @owner
          end
          real_name = OracleEnhanced::Quoting.valid_table_name?(name) ? name.upcase : name
          if real_name.include?(".")
            table_owner, table_name = real_name.split(".")
          else
            table_owner, table_name = default_owner, real_name
          end
          sql = <<~SQL.squish
            SELECT owner, table_name, 'TABLE' name_type
            FROM all_tables
            WHERE owner = :table_owner
              AND table_name = :table_name
            UNION ALL
            SELECT owner, view_name table_name, 'VIEW' name_type
            FROM all_views
            WHERE owner = :table_owner
              AND view_name = :table_name
            UNION ALL
            SELECT table_owner, table_name, 'SYNONYM' name_type
            FROM all_synonyms
            WHERE owner = :table_owner
              AND synonym_name = :table_name
            UNION ALL
            SELECT table_owner, table_name, 'SYNONYM' name_type
            FROM all_synonyms
            WHERE owner = 'PUBLIC'
              AND synonym_name = :real_name
          SQL
          if result = _select_one(sql, "CONNECTION", [table_owner, table_name, table_owner, table_name, table_owner, table_name, real_name])
            case result["name_type"]
            when "SYNONYM"
              describe("#{result['owner'] && "#{result['owner']}."}#{result['table_name']}")
            else
              [result["owner"], result["table_name"]]
            end
          else
            raise OracleEnhanced::ConnectionException, %Q{"DESC #{name}" failed; does it exist?}
          end
        end

        private
          # Oracle column names by default are case-insensitive, but treated as upcase;
          # for neatness, we'll downcase within Rails. EXCEPT that folks CAN quote
          # their column names when creating Oracle tables, which makes then case-sensitive.
          # I don't know anybody who does this, but we'll handle the theoretical case of a
          # camelCase column name. I imagine other dbs handle this different, since there's a
          # unit test that's currently failing test_oci.
          #
          # `_oracle_downcase` is expected to be called only from
          # `ActiveRecord::ConnectionAdapters::OracleEnhanced::OCIConnection`
          # or `ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection`.
          # Other method should call `ActiveRecord:: ConnectionAdapters::OracleEnhanced::Quoting#oracle_downcase`
          # since this is kind of quoting, not connection.
          # To avoid it is called from anywhere else, added _ at the beginning of the method name.
          def _oracle_downcase(column_name)
            return nil if column_name.nil?
            /[a-z]/.match?(column_name) ? column_name : column_name.downcase
          end

          # _select_one is expected to be called only from `DatabaseDescription#describe`.
          # Other methods should call `ActiveRecord::ConnectionAdapters::DatabaseStatements#select_one`.
          # To avoid being called from elsewhere a leading underscore is added.

          # Returns a record hash with the column names as keys and column values
          # as values.
          # binds is a array of native values in contrast to ActiveRecord::Relation::QueryAttribute
          def _select_one(arel, name = nil, binds = [])
            cursor = prepare(arel)
            cursor.bind_params(binds)
            cursor.exec
            columns = cursor.get_col_names.map do |col_name|
              _oracle_downcase(col_name)
            end
            row = cursor.fetch
            columns.each_with_index.to_h { |x, i| [x, row[i]] } if row
          ensure
            cursor.close
          end
      end
    end
  end
end
