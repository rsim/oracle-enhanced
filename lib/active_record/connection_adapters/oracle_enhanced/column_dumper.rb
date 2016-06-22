module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module ColumnDumper #:nodoc:

        def column_spec(column)
          spec = Hash[prepare_column_options(column).map { |k, v| [k, "#{k}: #{v}"] }]
          spec[:name] = column.name.inspect
          if column.virtual?
            spec[:type] = "virtual"
          else
            spec[:type] = schema_type(column).to_s
          end
          spec
        end

        def prepare_column_options(column)
          spec = {}

          if limit = schema_limit(column)
            spec[:limit] = limit
          end

          if precision = schema_precision(column)
            spec[:precision] = precision
          end

          if scale = schema_scale(column)
            spec[:scale] = scale
          end

          if virtual_as = schema_virtual_as(column)
            spec[:as] = virtual_as
          end

          if virtual_type = schema_virtual_type(column)
            spec[:virtual_type] = virtual_type
          end

          default = schema_default(column) if column.has_default?
          spec[:default]   = default unless default.nil?

          spec[:null] = 'false' unless column.null

          spec[:comment] = column.comment.inspect if column.comment.present?

          spec
        end

        def migration_keys
          # TODO `& column_specs.map(&:keys).flatten` should be exetuted here
          [:name, :limit, :precision, :scale, :default, :null, :as, :virtual_type, :comment]
        end

        private

        def schema_virtual_as(column)
          column.virtual_column_data_default if column.virtual?
        end

        def schema_virtual_type(column)
          unless column.type == :decimal
            column.type.inspect if column.virtual?
          end
        end

      end
    end
  end

  module ColumnDumper #:nodoc:
    prepend ConnectionAdapters::OracleEnhanced::ColumnDumper
  end
end
