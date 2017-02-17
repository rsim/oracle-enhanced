module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module ColumnDumper #:nodoc:
        def prepare_column_options(column)
          spec = super

          if supports_virtual_columns? && column.virtual?
            spec[:as] = column.virtual_column_data_default
            spec = { type: schema_type(column).inspect }.merge!(spec) unless column.type == :decimal
          end

          spec
        end

        private

          def default_primary_key?(column)
            schema_type(column) == :integer
          end
      end
    end
  end

  module ColumnDumper #:nodoc:
    prepend ConnectionAdapters::OracleEnhanced::ColumnDumper
  end
end
