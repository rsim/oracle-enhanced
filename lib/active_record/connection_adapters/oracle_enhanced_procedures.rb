require 'ruby_plsql'
require 'activesupport'

module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedProcedures #:nodoc:

      module ClassMethods
        def set_create_method(&block)
          self.custom_create_method = block
          # self.tables_with_create_method ||= {}
          # self.tables_with_create_method[table_name] = true
        end
      end
      
      module InstanceMethods
        def self.included(base)
          base.instance_eval do
            alias_method_chain :create, :custom_method
            private :create
          end
        end
        
        private
        
        def create_with_custom_method
          # RSI: check if class has custom create method
          return create_without_custom_method unless self.class.custom_create_method
          # TODO: should add logging similar to normal SQL statements
          self.id = self.class.custom_create_method.bind(self).call
          @new_record = false
          id
        end
      end

      # module AdapterInstanceMethods
      #   # Returns the last auto-generated ID from the affected table.
      #   def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
      #     # RSI: find out if class has custom create method
      #     klass = name
      #     create_method 
      #     execute(sql, name)
      #     id_value
      #   end
      # 
      #   # Executes the update statement and returns the number of rows affected.
      #   def update_sql(sql, name = nil)
      #     execute(sql, name)
      #   end
      # 
      #   # Executes the delete statement and returns the number of rows affected.
      #   def delete_sql(sql, name = nil)
      #     update_sql(sql, name)
      #   end
      # 
      #   def prefetch_primary_key?(table_name = nil)
      #     # RSI: check if table_name has custom create method
      #     !tables_with_create_method || !tables_with_create_method[table_name]
      #   end
      # 
      # end
      
    end
  end
end

ActiveRecord::Base.class_eval do
  class_inheritable_accessor :custom_create_method
  extend ActiveRecord::ConnectionAdapters::OracleEnhancedProcedures::ClassMethods
  include ActiveRecord::ConnectionAdapters::OracleEnhancedProcedures::InstanceMethods
end

# ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
#   include ActiveRecord::ConnectionAdapters::OracleEnhancedProcedures::AdapterInstanceMethods
# end