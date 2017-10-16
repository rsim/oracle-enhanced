# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module JDBCQuoting
        def _type_cast(value)
          case value
          when ActiveModel::Type::Binary::Data
            blob = Java::OracleSql::BLOB.createTemporary(@connection.raw_connection, false, Java::OracleSql::BLOB::DURATION_SESSION)
            blob.setBytes(1, value.to_s.to_java_bytes)
            blob
          when Type::OracleEnhanced::Text::Data
            clob = Java::OracleSql::CLOB.createTemporary(@connection.raw_connection, false, Java::OracleSql::CLOB::DURATION_SESSION)
            clob.setString(1, value.to_s)
            clob
          when Type::OracleEnhanced::NationalCharacterText::Data
            clob = Java::OracleSql::NCLOB.createTemporary(@connection.raw_connection, false, Java::OracleSql::NCLOB::DURATION_SESSION)
            clob.setString(1, value.to_s)
            clob
          else
            super
          end
        end
      end
    end
  end
end

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module Quoting
        prepend JDBCQuoting
      end
    end
  end
end
