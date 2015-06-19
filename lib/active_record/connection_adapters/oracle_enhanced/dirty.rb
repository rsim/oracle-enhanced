module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedDirty #:nodoc:

      module InstanceMethods #:nodoc:
        private

        def _field_changed?(attr, old_value)
          new_value = read_attribute(attr)
          raw_value = read_attribute_before_type_cast(attr)

          if self.class.columns_hash.include?(attr.to_s)
            column = column_for_attribute(attr)

            # Oracle stores empty string '' as NULL
            # therefore need to convert empty string value to nil if old value is nil
            if column.type == :string && column.null && old_value.nil?
              new_value = nil if new_value == ''
            end
            column.changed?(old_value, new_value, raw_value)
          else
            new_value != old_value
          end
        end

        def non_zero?(value)
          value !~ /\A0+(\.0+)?\z/
        end 
        
      end

    end
  end
end

if ActiveRecord::Base.method_defined?(:changed?)
  ActiveRecord::Base.class_eval do
    include ActiveRecord::ConnectionAdapters::OracleEnhancedDirty::InstanceMethods
  end
end
