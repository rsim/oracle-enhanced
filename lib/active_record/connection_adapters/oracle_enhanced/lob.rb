# frozen_string_literal: true

module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module Lob #:nodoc:
        extend ActiveSupport::Concern

        included do
          class_attribute :custom_create_method, :custom_update_method, :custom_delete_method

          # After setting large objects to empty, select the OCI8::LOB
          # and write back the data.
          before_update :record_changed_lobs
          after_update :enhanced_write_lobs
        end

        module ClassMethods
          def lob_columns
            columns.select do |column|
              column.sql_type_metadata.sql_type.end_with?("LOB")
            end
          end
        end

        private
          def enhanced_write_lobs
            if self.class.connection.is_a?(ConnectionAdapters::OracleEnhancedAdapter) &&
                !(self.class.custom_create_method || self.class.custom_update_method)
              self.class.connection.write_lobs(self.class.table_name, self.class, attributes, @changed_lob_columns)
            end
          end
          def record_changed_lobs
            @changed_lob_columns = self.class.lob_columns.select do |col|
              self.will_save_change_to_attribute?(col.name) && !self.class.readonly_attributes.to_a.include?(col.name)
            end
          end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.send(:include, ActiveRecord::ConnectionAdapters::OracleEnhanced::Lob)
end
