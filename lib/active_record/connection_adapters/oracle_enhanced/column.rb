# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        attr_reader :table_name, :nchar, :virtual_column_data_default, :returning_id #:nodoc:

        def initialize(name, default, sql_type_metadata = nil, null = true, table_name = nil, virtual = false, returning_id = nil, comment = nil) #:nodoc:
          @virtual = virtual
          @virtual_column_data_default = default.inspect if virtual
          @returning_id = returning_id
          if virtual
            default_value = nil
          else
            default_value = self.class.extract_value_from_default(default)
          end
          super(name, default_value, sql_type_metadata, null, table_name, comment: comment)
          # Is column NCHAR or NVARCHAR2 (will need to use N'...' value quoting for these data types)?
          # Define only when needed as adapter "quote" method will check at first if instance variable is defined.
        end

        def virtual?
          @virtual
        end

        def returning_id?
          @returning_id
        end

        def lob?
          self.sql_type =~ /LOB$/i
        end

      private

        def self.extract_value_from_default(default)
          case default
          when String
            default.gsub(/''/, "'")
            else
            default
          end
        end
      end
    end
  end
end
