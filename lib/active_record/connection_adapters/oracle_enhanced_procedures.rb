# define accessors before requiring ruby-plsql as these accessors are used in clob writing callback and should be
# available also if ruby-plsql could not be loaded
ActiveRecord::Base.class_eval do
  class_inheritable_accessor :custom_create_method, :custom_update_method, :custom_delete_method
end

require 'ruby_plsql'
require 'activesupport'

module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedProcedures #:nodoc:

      module ClassMethods
        # Specify custom create method which should be used instead of Rails generated INSERT statement.
        # Provided block should return ID of new record.
        # Example:
        #   set_create_method do
        #     plsql.employees_pkg.create_employee(
        #       :p_first_name => first_name,
        #       :p_last_name => last_name,
        #       :p_employee_id => nil
        #     )[:p_employee_id]
        #   end
        def set_create_method(&block)
          include_with_custom_methods
          self.custom_create_method = block
        end

        # Specify custom update method which should be used instead of Rails generated UPDATE statement.
        # Example:
        #   set_update_method do
        #     plsql.employees_pkg.update_employee(
        #       :p_employee_id => id,
        #       :p_first_name => first_name,
        #       :p_last_name => last_name
        #     )
        #   end
        def set_update_method(&block)
          include_with_custom_methods
          self.custom_update_method = block
        end

        # Specify custom delete method which should be used instead of Rails generated DELETE statement.
        # Example:
        #   set_delete_method do
        #     plsql.employees_pkg.delete_employee(
        #       :p_employee_id => id
        #     )
        #   end
        def set_delete_method(&block)
          include_with_custom_methods
          self.custom_delete_method = block
        end
        
        private
        def include_with_custom_methods
          unless included_modules.include? InstanceMethods
            include InstanceMethods
          end
        end
      end
      
      module InstanceMethods #:nodoc:
        def self.included(base)
          base.instance_eval do
            if private_instance_methods.include?('create_without_callbacks') || private_instance_methods.include?(:create_without_callbacks)
              alias_method :create_without_custom_method, :create_without_callbacks
              alias_method :create_without_callbacks, :create_with_custom_method
            else
              alias_method_chain :create, :custom_method
            end
            # insert after dirty checking in Rails 2.1
            # in Ruby 1.9 methods names are returned as symbols
            if private_instance_methods.include?('update_without_dirty') || private_instance_methods.include?(:update_without_dirty)
              alias_method :update_without_custom_method, :update_without_dirty
              alias_method :update_without_dirty, :update_with_custom_method
            elsif private_instance_methods.include?('update_without_callbacks') || private_instance_methods.include?(:update_without_callbacks)
              alias_method :update_without_custom_method, :update_without_callbacks
              alias_method :update_without_callbacks, :update_with_custom_method
            else
              alias_method_chain :update, :custom_method
            end
            private :create, :update
            if public_instance_methods.include?('destroy_without_callbacks') || public_instance_methods.include?(:destroy_without_callbacks)
              alias_method :destroy_without_custom_method, :destroy_without_callbacks
              alias_method :destroy_without_callbacks, :destroy_with_custom_method
            else
              alias_method_chain :destroy, :custom_method
            end
            public :destroy
          end
        end
        
        private
        
        # Creates a record with custom create method
        # and returns its id.
        def create_with_custom_method
          # check if class has custom create method
          return create_without_custom_method unless self.class.custom_create_method
          self.class.connection.log_custom_method("custom create method", "#{self.class.name} Create") do
            self.id = self.class.custom_create_method.bind(self).call
          end
          @new_record = false
          id
        end

        # Updates the associated record with custom update method
        # Returns the number of affected rows.
        def update_with_custom_method(attribute_names = @attributes.keys)
          # check if class has custom create method
          return update_without_custom_method unless self.class.custom_update_method
          return 0 if attribute_names.empty?
          self.class.connection.log_custom_method("custom update method with #{self.class.primary_key}=#{self.id}", "#{self.class.name} Update") do
            self.class.custom_update_method.bind(self).call
          end
          1
        end

        # Deletes the record in the database with custom delete method
        # and freezes this instance to reflect that no changes should
        # be made (since they can't be persisted).
        def destroy_with_custom_method
          # check if class has custom create method
          return destroy_without_custom_method unless self.class.custom_delete_method
          unless new_record?
            self.class.connection.log_custom_method("custom delete method with #{self.class.primary_key}=#{self.id}", "#{self.class.name} Destroy") do
              self.class.custom_delete_method.bind(self).call
            end
          end

          freeze
        end

      end

    end
  end
end

ActiveRecord::Base.class_eval do
  extend ActiveRecord::ConnectionAdapters::OracleEnhancedProcedures::ClassMethods
end

ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
  # public alias to log method which could be used from other objects
  alias_method :log_custom_method, :log
  public :log_custom_method
end
