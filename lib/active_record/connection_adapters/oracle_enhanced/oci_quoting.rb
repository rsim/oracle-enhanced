# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module OCIQuoting
        def type_cast(value)
          case value
          when ActiveModel::Type::Binary::Data
            lob_value = value == "" ? " " : value
            bind_type = OCI8::BLOB
            ora_value = bind_type.new(_connection.raw_oci_connection, lob_value)
            ora_value.size = 0 if value == ""
            ora_value
          when Type::OracleEnhanced::Text::Data
            lob_value = value.to_s == "" ? " " : value.to_s
            bind_type = OCI8::CLOB
            ora_value = bind_type.new(_connection.raw_oci_connection, lob_value)
            ora_value.size = 0 if value.to_s == ""
            ora_value
          when Type::OracleEnhanced::NationalCharacterText::Data
            lob_value = value.to_s == "" ? " " : value.to_s
            bind_type = OCI8::NCLOB
            ora_value = bind_type.new(_connection.raw_oci_connection, lob_value)
            ora_value.size = 0 if value.to_s == ""
            ora_value
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
        prepend OCIQuoting
      end
    end
  end
end
