# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced
      class Column < ActiveRecord::ConnectionAdapters::Column
        attr_reader :virtual_column_data_default #:nodoc:

        def initialize(name, default, sql_type_metadata = nil, null = true, table_name = nil, virtual = false, comment = nil) #:nodoc:
          @virtual = virtual
          @virtual_column_data_default = default.inspect if virtual
          if virtual
            default_value = nil
          else
            default_value = self.class.extract_value_from_default(default)
          end
          super(name, default_value, sql_type_metadata, null, table_name, comment: comment)
        end

        def virtual?
          @virtual
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
