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
          when ActiveModel::Type::Binary::Data then
            "empty_blob()"
          when Type::OracleEnhanced::Text::Data then
            "empty_clob()"
          when Type::OracleEnhanced::NationalCharacterText::Data then
            "empty_nclob()"
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
