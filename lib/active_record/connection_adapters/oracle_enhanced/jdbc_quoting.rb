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
          when ActiveRecord::OracleEnhanced::Type::Text::Data
            clob = Java::OracleSql::CLOB.createTemporary(@connection.raw_connection, false, Java::OracleSql::CLOB::DURATION_SESSION)
            clob.setString(1, value.to_s)
            clob
          when Date, DateTime
            Java::oracle.sql.DATE.new(value.strftime("%Y-%m-%d %H:%M:%S"))
          when Time
            Java::java.sql.Timestamp.new(value.year-1900, value.month-1, value.day, value.hour, value.min, value.sec, value.usec * 1000)
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
