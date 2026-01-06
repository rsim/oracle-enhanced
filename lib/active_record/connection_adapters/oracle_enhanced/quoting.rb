# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module Quoting
        extend ActiveSupport::Concern
        # QUOTING ==================================================
        #
        # see: abstract/quoting.rb
        QUOTED_COLUMN_NAMES = Concurrent::Map.new # :nodoc:
        QUOTED_TABLE_NAMES = Concurrent::Map.new # :nodoc:

        module ClassMethods # :nodoc:
          def column_name_matcher
            /
          \A
          (
            (?:
              # "table_name"."column_name" | function(one or no argument)
              ((?:\w+\.|"\w+"\.)?(?:\w+|"\w+") | \w+\((?:|\g<2>)\))
            )
            (?:(?:\s+AS)?\s+(?:\w+|"\w+"))?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix
          end

          def column_name_with_order_matcher
            /
          \A
          (
            (?:
              # "table_name"."column_name" | function(one or no argument)
              ((?:\w+\.|"\w+"\.)?(?:\w+|"\w+") | \w+\((?:|\g<2>)\))
            )
            (?:\s+ASC|\s+DESC)?
            (?:\s+NULLS\s+(?:FIRST|LAST))?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix
          end

          def quote_column_name(name) # :nodoc:
            name = name.to_s
            QUOTED_COLUMN_NAMES[name] ||= if /\A[a-z][a-z_0-9$#]*\Z/.match?(name)
              "\"#{name.upcase}\""
            else
              # remove double quotes which cannot be used inside quoted identifier
              "\"#{name.delete('"')}\""
            end
          end

          def quote_table_name(name) # :nodoc:
            name, _link = name.to_s.split("@")
            QUOTED_TABLE_NAMES[name] ||= [name.split(".").map { |n| quote_column_name(n) }].join(".")
          end
        end

        # Oracle SQL VARCHAR2 limit for string literals is 4000 bytes normally.
        # Server MAX_STRING_SIZE=EXTENDED will increase this to 32767 (32KB - 1).
        # Using 1000 chars to be safe with multi-byte UTF-8 (max 4 bytes/char).
        SQL_UTF8_CHUNK_CHARS = 1000

        # Maximum BLOB size that can be inlined using hextoraw().
        # With MAX_STRING_SIZE=EXTENDED this is 16383 bytes (32766 hex chars).
        # Using 2000 bytes (4000 hex chars) to be safe with standard config.
        BLOB_INLINE_LIMIT = 2000

        # Chunk size for large BLOBs using DBMS_LOB.WRITEAPPEND with base64.
        # Base64 encodes 3 bytes into 4 chars. With VARCHAR2 max of 32767 chars,
        # we can encode floor(32767/4)*3 = 24573 bytes per chunk.
        PLSQL_BASE64_CHUNK_SIZE = 24_573

        # This method is used in add_index to identify either column name (which is quoted)
        # or function based index (in which case function expression is not quoted)
        def quote_column_name_or_expression(name) # :nodoc:
          name = name.to_s
          case name
          # if only valid lowercase column characters in name
          when /^[a-z][a-z_0-9$#]*$/
            "\"#{name.upcase}\""
          when /^[a-z][a-z_0-9$#-]*$/i
            "\"#{name}\""
          # if other characters present then assume that it is expression
          # which should not be quoted
          else
            name
          end
        end

        # Names must be from 1 to 30 bytes long with these exceptions:
        # * Names of databases are limited to 8 bytes.
        # * Names of database links can be as long as 128 bytes.
        #
        # Nonquoted identifiers cannot be Oracle Database reserved words
        #
        # Nonquoted identifiers must begin with an alphabetic character from
        # your database character set
        #
        # Nonquoted identifiers can contain only alphanumeric characters from
        # your database character set and the underscore (_), dollar sign ($),
        # and pound sign (#).
        # Oracle strongly discourages you from using $ and # in nonquoted identifiers.
        NONQUOTED_OBJECT_NAME = /[[:alpha:]][\w$#]{0,29}/
        VALID_TABLE_NAME = /\A(?:#{NONQUOTED_OBJECT_NAME}\.)?#{NONQUOTED_OBJECT_NAME}?\Z/

        # unescaped table name should start with letter and
        # contain letters, digits, _, $ or #
        # can be prefixed with schema name
        # CamelCase table names should be quoted
        def self.valid_table_name?(name) # :nodoc:
          object_name = name.to_s
          !!(object_name =~ VALID_TABLE_NAME && !mixed_case?(object_name))
        end

        def self.mixed_case?(name)
          object_name = name.include?(".") ? name.split(".").second : name
          !!(object_name =~ /[A-Z]/ && object_name =~ /[a-z]/)
        end

        def quote_string(s) # :nodoc:
          s.gsub(/'/, "''")
        end

        def quote(value) # :nodoc:
          case value
          when Type::OracleEnhanced::CharacterString::Data then
            "'#{quote_string(value.to_s)}'"
          when Type::OracleEnhanced::NationalCharacterString::Data then
            +"N" << "'#{quote_string(value.to_s)}'"
          when ActiveModel::Type::Binary::Data
            data = value.to_s
            if data.empty?
              "empty_blob()"
            elsif data.bytesize <= BLOB_INLINE_LIMIT
              "to_blob(hextoraw('#{data.unpack1('H*')}'))"
            else
              quote_blob_as_subquery(data)
            end
          when Type::OracleEnhanced::Text::Data
            text = value.to_s
            text.empty? ? "empty_clob()" :
              value.to_s.scan(/.{1,#{SQL_UTF8_CHUNK_CHARS}}/m)
                   .map { |chunk| "to_clob('#{quote_string(chunk)}')" }
                   .join(" || ")
          when Type::OracleEnhanced::NationalCharacterText::Data
            text = value.to_s
            text.empty? ? "empty_clob()" :
            value.to_s.scan(/.{1,#{SQL_UTF8_CHUNK_CHARS}}/m)
                .map { |chunk| "to_nclob(N'#{quote_string(chunk)}')" }
                .join(" || ")
          else
            super
          end
        end

        def quoted_true # :nodoc:
          return "'Y'" if emulate_booleans_from_strings
          "1"
        end

        def unquoted_true # :nodoc:
          return "Y" if emulate_booleans_from_strings
          "1"
        end

        def quoted_false # :nodoc:
          return "'N'" if emulate_booleans_from_strings
          "0"
        end

        def unquoted_false # :nodoc:
          return "N" if emulate_booleans_from_strings
          "0"
        end

        def type_cast(value)
          case value
          when Type::OracleEnhanced::TimestampTz::Data, Type::OracleEnhanced::TimestampLtz::Data
            if value.acts_like?(:time)
              zone_conversion_method = ActiveRecord.default_timezone == :utc ? :getutc : :getlocal
              value.respond_to?(zone_conversion_method) ? value.send(zone_conversion_method) : value
            else
              value
            end
          when Type::OracleEnhanced::NationalCharacterString::Data
            value.to_s
          when Type::OracleEnhanced::CharacterString::Data
            value
          else
            super
          end
        end

        private
          def oracle_downcase(column_name)
            return nil if column_name.nil?
            /[a-z]/.match?(column_name) ? column_name : column_name.downcase
          end

          # Generate a scalar subquery with PL/SQL function to build large BLOBs.
          # Uses DBMS_LOB.WRITEAPPEND with base64-encoded chunks for efficiency.
          # Testing showed hextoraw() unusable for being more than 100x slower.
          def quote_blob_as_subquery(data)
            out = +""
            out << "(\n"
            out << "  WITH FUNCTION make_blob RETURN BLOB IS\n"
            out << "    l_blob BLOB;\n"
            out << "  BEGIN\n"
            out << "    DBMS_LOB.CREATETEMPORARY(l_blob, TRUE, DBMS_LOB.CALL);\n"

            offset = 0
            while offset < data.bytesize
              chunk = data.byteslice(offset, PLSQL_BASE64_CHUNK_SIZE)
              out << "    DBMS_LOB.WRITEAPPEND(l_blob, "
              out << chunk.bytesize.to_s
              out << ", UTL_ENCODE.BASE64_DECODE(UTL_RAW.CAST_TO_RAW('"
              out << [chunk].pack("m0")  # Base64 encoding without newlines
              out << "')));\n"
              offset += PLSQL_BASE64_CHUNK_SIZE
            end

            out << "    RETURN l_blob;\n"
            out << "  END;\n"
            out << "  SELECT make_blob() FROM dual\n"
            out << ")"
            out
          end
      end
    end
  end
end

# if MRI or YARV or TruffleRuby
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby" || RUBY_ENGINE == "truffleruby"
  require "active_record/connection_adapters/oracle_enhanced/oci_quoting"
# if JRuby
elsif RUBY_ENGINE == "jruby"
  require "active_record/connection_adapters/oracle_enhanced/jdbc_quoting"
else
  raise "Unsupported Ruby engine #{RUBY_ENGINE}"
end
