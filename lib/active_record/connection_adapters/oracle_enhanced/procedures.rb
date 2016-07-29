require 'active_support'

module ActiveRecord #:nodoc:
  # Custom create, update, delete methods functionality.
  # 
  # Example:
  #
  #   class Employee < ActiveRecord::Base
  #     include ActiveRecord::OracleEnhancedProcedures
  #
  #     set_create_method do
  #       plsql.employees_pkg.create_employee(
  #         :p_first_name => first_name,
  #         :p_last_name => last_name,
  #         :p_employee_id => nil
  #       )[:p_employee_id]
  #     end
  #
  #     set_update_method do
  #       plsql.employees_pkg.update_employee(
  #         :p_employee_id => id,
  #         :p_first_name => first_name,
  #         :p_last_name => last_name
  #       )
  #     end
  #
  #     set_delete_method do
  #       plsql.employees_pkg.delete_employee(
  #         :p_employee_id => id
  #       )
  #     end
  #   end
  #
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
        self.custom_delete_method = block
      end
    end

    def self.included(base)
      base.class_eval do
        extend ClassMethods
        class_attribute :custom_create_method
        class_attribute :custom_update_method
        class_attribute :custom_delete_method
      end
    end

    def destroy #:nodoc:
      # check if class has custom delete method
      if self.class.custom_delete_method
        # wrap destroy in transaction
        with_transaction_returning_status do
          # run before/after callbacks defined in model
          run_callbacks(:destroy) { destroy_using_custom_method }
        end
      else
        super
      end
    end

    private

    # Creates a record with custom create method
    # and returns its id.
    def _create_record
      # check if class has custom create method
      if self.class.custom_create_method
        # run before/after callbacks defined in model
        run_callbacks(:create) do
          # timestamp
          if self.record_timestamps
            current_time = current_time_from_proper_timezone

            all_timestamp_attributes.each do |column|
              if respond_to?(column) && respond_to?("#{column}=") && self.send(column).nil?
                write_attribute(column.to_s, current_time)
              end
            end
          end
          # run
          create_using_custom_method
        end
      else
        super
      end
    end

    def create_using_custom_method
      log_custom_method("custom create method", "#{self.class.name} Create") do
        self.id = instance_eval(&self.class.custom_create_method)
      end
      @new_record = false
      # Starting from ActiveRecord 3.0.3 @persisted is used instead of @new_record
      @persisted = true
      id
    end

    # Updates the associated record with custom update method
    # Returns the number of affected rows.
    def _update_record(attribute_names = @attributes.keys)
      # check if class has custom update method
      if self.class.custom_update_method
        # run before/after callbacks defined in model
        run_callbacks(:update) do
          # timestamp
          if should_record_timestamps?
            current_time = current_time_from_proper_timezone

            timestamp_attributes_for_update_in_model.each do |column|
              column = column.to_s
              next if attribute_changed?(column)
              write_attribute(column, current_time)
            end
          end
          # update just dirty attributes
          if partial_writes?
            # Serialized attributes should always be written in case they've been
            # changed in place.
            update_using_custom_method(changed | (attributes.keys & self.class.columns.select {|column| column.is_a?(Type::Serialized)}))
          else
            update_using_custom_method(attributes.keys)
          end
        end
      else
        super
      end
    end

    def update_using_custom_method(attribute_names)
      return 0 if attribute_names.empty?
      log_custom_method("custom update method with #{self.class.primary_key}=#{self.id}", "#{self.class.name} Update") do
        instance_eval(&self.class.custom_update_method)
      end
      1
    end

    # Deletes the record in the database with custom delete method
    # and freezes this instance to reflect that no changes should
    # be made (since they can't be persisted).
    def destroy_using_custom_method
      unless new_record? || @destroyed
        log_custom_method("custom delete method with #{self.class.primary_key}=#{self.id}", "#{self.class.name} Destroy") do
          instance_eval(&self.class.custom_delete_method)
        end
      end

      @destroyed = true
      freeze
    end

    def log_custom_method(*args)
      self.class.connection.send(:log, *args) { yield }
    end

    alias_method :update_record, :_update_record if private_method_defined?(:_update_record)
    alias_method :create_record, :_create_record if private_method_defined?(:_create_record)
  end
end
