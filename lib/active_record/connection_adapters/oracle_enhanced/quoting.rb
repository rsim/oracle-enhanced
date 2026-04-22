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

        # Nonquoted Oracle identifiers must begin with an alphabetic
        # character from the database character set and may contain only
        # alphanumerics plus +_+, +$+, and +#+. Oracle strongly discourages
        # +$+ and +#+ in nonquoted names. Byte limits depend on the
        # identifier class: 30 bytes on pre-12.2 databases, 128 bytes on
        # 12.2+ for schema objects; Oracle enforces the limit per
        # identifier (per component of a +schema.name+ pair), not on the
        # full qualified string. Mixed-case names are rejected here so
        # callers quote them explicitly.

        # Returns true when +name+ is a valid unquoted Oracle schema-object
        # name (optionally schema-qualified as +schema.name+). The
        # +max_identifier_length+ bound is applied per component because
        # Oracle enforces the byte limit on each identifier, not on the
        # full +schema.table+ string. Omitting the argument is deprecated
        # and falls back to the legacy 30 byte bound with a warning.
        #
        # The grammar regex has mixed Unicode semantics: +[[:alpha:]]+
        # accepts Unicode letters as the first character but +\w+ stays
        # ASCII-only, so any non-ASCII character beyond the first position
        # is rejected. Oracle itself accepts database-character-set letters
        # throughout unquoted identifiers on AL32UTF8, so this is stricter
        # than Oracle. A future change could add the +/u+ flag or use
        # +[[:word:]]+; for now the bytesize check is preserved as the
        # intended byte boundary for when the grammar is relaxed.
        def self.valid_table_name?(name, max_identifier_length: nil) # :nodoc:
          if max_identifier_length.nil?
            OracleEnhanced.deprecator.deprecation_warning(
              "ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting.valid_table_name? called without `max_identifier_length:`",
              "pass `max_identifier_length:` explicitly; the implicit 30 byte default will be removed"
            )
            max_identifier_length = 30
          end
          object_name = name.to_s
          # Grammar only: no length bound here; `\w` is ASCII-only so non-ASCII letters after the first character are rejected (stricter than Oracle on AL32UTF8).
          return false unless /\A(?:[[:alpha:]][\w$#]*\.)?[[:alpha:]][\w$#]*\Z/.match?(object_name)
          # Byte limit is enforced per component — Oracle applies the limit to each identifier, not to the full `schema.table` string.
          return false unless object_name.split(".").all? { |part| part.bytesize <= max_identifier_length }
          !mixed_case?(object_name)
        end

        def self.mixed_case?(name)
          object_name = name.include?(".") ? name.split(".").second : name
          !!(object_name =~ /[A-Z]/ && object_name =~ /[a-z]/)
        end

        # Deprecated. +NONQUOTED_OBJECT_NAME+ and +VALID_TABLE_NAME+ are
        # resolved here so external references keep their pre-deprecation
        # values (30 byte grammar) with a warning routed through the shared
        # deprecator. New code should use +valid_table_name?+.
        #
        # Note: direct reads (+Quoting::VALID_TABLE_NAME+) still work; reflection
        # APIs (+const_defined?+, +defined?+, +.constants+) do not see these
        # names because nothing is actually declared.
        def self.const_missing(name)
          case name
          when :NONQUOTED_OBJECT_NAME
            OracleEnhanced.deprecator.deprecation_warning(
              "ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting::NONQUOTED_OBJECT_NAME",
              "use `valid_table_name?` instead"
            )
            /[[:alpha:]][\w$#]{0,29}/
          when :VALID_TABLE_NAME
            OracleEnhanced.deprecator.deprecation_warning(
              "ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting::VALID_TABLE_NAME",
              "use `valid_table_name?` instead"
            )
            /\A(?:[[:alpha:]][\w$#]{0,29}\.)?[[:alpha:]][\w$#]{0,29}\Z/
          else
            super
          end
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

          # Also expose `oracle_downcase` as `Quoting.oracle_downcase(...)` so the raw-driver
          # `select` paths in OCIConnection / JDBCConnection can reuse it without mixing in
          # the whole Quoting module. It stays a private instance method when Quoting is
          # included into the adapter.
          module_function :oracle_downcase
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
