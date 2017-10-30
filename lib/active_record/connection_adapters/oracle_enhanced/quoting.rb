# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module Quoting
        # QUOTING ==================================================
        #
        # see: abstract/quoting.rb

        def quote_column_name(name) #:nodoc:
          name = name.to_s
          @quoted_column_names[name] ||= begin
            # if only valid lowercase column characters in name
            if name =~ /\A[a-z][a-z_0-9\$#]*\Z/
              "\"#{name.upcase}\""
            else
              # remove double quotes which cannot be used inside quoted identifier
              "\"#{name.gsub('"', '')}\""
            end
          end
        end

        # This method is used in add_index to identify either column name (which is quoted)
        # or function based index (in which case function expression is not quoted)
        def quote_column_name_or_expression(name) #:nodoc:
          name = name.to_s
          case name
          # if only valid lowercase column characters in name
          when /^[a-z][a-z_0-9\$#]*$/
            "\"#{name.upcase}\""
          when /^[a-z][a-z_0-9\$#\-]*$/i
            "\"#{name}\""
          # if other characters present then assume that it is expression
          # which should not be quoted
          else
            name
          end
        end

        # Used only for quoting database links as the naming rules for links
        # differ from the rules for column names. Specifically, link names may
        # include periods.
        def quote_database_link(name)
          case name
          when NONQUOTED_DATABASE_LINK
            %Q("#{name.upcase}")
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
        # and pound sign (#). Database links can also contain periods (.) and
        # "at" signs (@). Oracle strongly discourages you from using $ and # in
        # nonquoted identifiers.
        NONQUOTED_OBJECT_NAME   = /[[:alpha:]][\w$#]{0,29}/
        NONQUOTED_DATABASE_LINK = /[[:alpha:]][\w$#\.@]{0,127}/
        VALID_TABLE_NAME = /\A(?:#{NONQUOTED_OBJECT_NAME}\.)?#{NONQUOTED_OBJECT_NAME}(?:@#{NONQUOTED_DATABASE_LINK})?\Z/

        # unescaped table name should start with letter and
        # contain letters, digits, _, $ or #
        # can be prefixed with schema name
        # CamelCase table names should be quoted
        def self.valid_table_name?(name) #:nodoc:
          object_name = name.to_s
          !!(object_name =~ VALID_TABLE_NAME && !mixed_case?(object_name))
        end

        def self.mixed_case?(name)
          object_name = name.include?(".") ? name.split(".").second : name
          !!(object_name =~ /[A-Z]/ && object_name =~ /[a-z]/)
        end

        def quote_table_name(name) #:nodoc:
          name, link = name.to_s.split("@")
          @quoted_table_names[name] ||= [name.split(".").map { |n| quote_column_name(n) }.join("."), quote_database_link(link)].compact.join("@")
        end

        def quote_string(s) #:nodoc:
          s.gsub(/'/, "''")
        end

        def _quote(value) #:nodoc:
          case value
          when Type::OracleEnhanced::NationalCharacterString::Data then
            "N".dup << "'#{quote_string(value.to_s)}'"
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

        def quoted_true #:nodoc:
          return "'Y'" if emulate_booleans_from_strings
          "1".freeze
        end

        def unquoted_true #:nodoc:
          return "Y" if emulate_booleans_from_strings
          "1".freeze
        end

        def quoted_false #:nodoc:
          return "'N'" if emulate_booleans_from_strings
          "0".freeze
        end

        def unquoted_false #:nodoc:
          return "N" if emulate_booleans_from_strings
          "0".freeze
        end

        def _type_cast(value)
          case value
          when Type::OracleEnhanced::TimestampTz::Data, Type::OracleEnhanced::TimestampLtz::Data
            if value.acts_like?(:time)
              zone_conversion_method = ActiveRecord::Base.default_timezone == :utc ? :getutc : :getlocal
              value.respond_to?(zone_conversion_method) ? value.send(zone_conversion_method) : value
            else
              value
            end
          when Type::OracleEnhanced::NationalCharacterString::Data
            value.to_s
          else
            super
          end
        end

        private

          def oracle_downcase(column_name)
            return nil if column_name.nil?
            column_name =~ /[a-z]/ ? column_name : column_name.downcase
          end
      end
    end
  end
end

# if MRI or YARV
if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby"
  require "active_record/connection_adapters/oracle_enhanced/oci_quoting"
# if JRuby
elsif RUBY_ENGINE == "jruby"
  require "active_record/connection_adapters/oracle_enhanced/jdbc_quoting"
else
  raise "Unsupported Ruby engine #{RUBY_ENGINE}"
end
