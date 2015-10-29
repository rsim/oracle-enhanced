module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module ColumnDumper #:nodoc:
        def self.included(base) #:nodoc:
          base.class_eval do
            private
            alias_method_chain :column_spec,            :oracle_enhanced
            alias_method_chain :prepare_column_options, :oracle_enhanced
            alias_method_chain :migration_keys,         :oracle_enhanced

            def oracle_enhanced_adapter?
            # return original method if not using 'OracleEnhanced'
              if (rails_env = defined?(Rails.env) ? Rails.env : (defined?(RAILS_ENV) ? RAILS_ENV : nil)) &&
                  ActiveRecord::Base.configurations[rails_env] &&
                  ActiveRecord::Base.configurations[rails_env]['adapter'] != 'oracle_enhanced'
                return false
              else
                return true
              end
            end
          end
        end

        def column_spec_with_oracle_enhanced(column, types)
          # return original method if not using 'OracleEnhanced'
          return column_spec_without_oracle_enhanced(column, types) unless oracle_enhanced_adapter?

          spec = prepare_column_options(column, types)
          (spec.keys - [:name, :type]).each do |k|
            key_s = (k == :virtual_type ? "type: " : "#{k.to_s}: ")
            spec[k] = key_s + spec[k]
          end
          spec
        end

        def prepare_column_options_with_oracle_enhanced(column, types)
          # return original method if not using 'OracleEnhanced'
          return prepare_column_options_without_oracle_enhanced(column, types) unless oracle_enhanced_adapter?

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
          spec[:comment]   = column.comment.inspect unless column.comment.nil?
          spec.delete(:default) if spec[:default].nil?
          spec
        end

        def migration_keys_with_oracle_enhanced
          # TODO `& column_specs.map(&:keys).flatten` should be exetuted here
          # return original method if not using 'OracleEnhanced'
          return migration_keys_without_oracle_enhanced unless oracle_enhanced_adapter?

          [:name, :limit, :precision, :scale, :default, :null, :as, :virtual_type, :comment]
        end
      end
    end
  end
end
