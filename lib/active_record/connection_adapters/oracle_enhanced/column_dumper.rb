module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module ColumnDumper #:nodoc:

        def column_spec(column, types)
          spec = prepare_column_options(column, types)
          (spec.keys - [:name, :type]).each do |k|
            key_s = (k == :virtual_type ? "type: " : "#{k.to_s}: ")
            spec[k] = key_s + spec[k]
          end
          spec
        end

        def prepare_column_options(column, types)
          spec = {}
          spec[:name]      = column.name.inspect
          spec[:type]      = column.virtual? ? 'virtual' : column.type.to_s
          spec[:virtual_type] = column.type.inspect if column.virtual? && column.sql_type != 'NUMBER'
          spec[:limit]     = column.limit.inspect if column.limit != types[column.type][:limit] && column.type != :decimal
          spec[:precision] = column.precision.inspect if !column.precision.nil?
          spec[:scale]     = column.scale.inspect if !column.scale.nil?
          spec[:null]      = 'false' if !column.null
          spec[:as]        = column.virtual_column_data_default if column.virtual?
          spec[:default]   = schema_default(column) if column.has_default? && !column.virtual?
          spec.delete(:default) if spec[:default].nil?
          spec
        end

        def migration_keys
          # TODO `& column_specs.map(&:keys).flatten` should be exetuted here
          [:name, :limit, :precision, :scale, :default, :null, :as, :virtual_type]
        end
      end
    end
  end

  module ColumnDumper #:nodoc:
    prepend ConnectionAdapters::OracleEnhanced::ColumnDumper
  end
end
