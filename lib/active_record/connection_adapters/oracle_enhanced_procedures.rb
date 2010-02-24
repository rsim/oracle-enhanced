# define accessors before requiring ruby-plsql as these accessors are used in clob writing callback and should be
# available also if ruby-plsql could not be loaded
ActiveRecord::Base.class_eval do
  class_inheritable_accessor :custom_create_method, :custom_update_method, :custom_delete_method
end

require 'active_support'

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
        
        def create_method_name_before_custom_methods #:nodoc:
          if private_method_defined?(:create_without_timestamps) && defined?(ActiveRecord::VERSION) && ActiveRecord::VERSION::STRING.to_f >= 2.3
            :create_without_timestamps
          elsif private_method_defined?(:create_without_callbacks)
            :create_without_callbacks
          else
            :create
          end
        end
        
        def update_method_name_before_custom_methods #:nodoc:
          if private_method_defined?(:update_without_dirty)
            :update_without_dirty
          elsif private_method_defined?(:update_without_timestamps) && defined?(ActiveRecord::VERSION) && ActiveRecord::VERSION::STRING.to_f >= 2.3
            :update_without_timestamps
          elsif private_method_defined?(:update_without_callbacks)
            :update_without_callbacks
          else
            :update
          end
        end
        
        def destroy_method_name_before_custom_methods #:nodoc:
          if public_method_defined?(:destroy_without_callbacks)
            :destroy_without_callbacks
          else
            :destroy
          end
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
            alias_method :create_without_custom_method, create_method_name_before_custom_methods
            alias_method create_method_name_before_custom_methods, :create_with_custom_method
            alias_method :update_without_custom_method, update_method_name_before_custom_methods
            alias_method update_method_name_before_custom_methods, :update_with_custom_method
            alias_method :destroy_without_custom_method, destroy_method_name_before_custom_methods
            alias_method destroy_method_name_before_custom_methods, :destroy_with_custom_method
            private :create, :update
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

          @destroyed = true
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
