module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module JDBCQuoting
        def _type_cast(value)
          case value
          when ActiveModel::Type::Binary::Data
            #TODO: may need BLOB specific handling
            value
          when ActiveRecord::OracleEnhanced::Type::Text::Data
            #TODO: may need CLOB specific handling
            value.to_s
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
