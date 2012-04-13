module ActiveRecord
  module OracleEnhancedModel
    module ClassMethods
      # TODO: Remove this when https://github.com/rails/rails/pull/5832/files gets merged in
      def reset_sequence_name #:nodoc:
        @explicit_sequence_name = false
        @sequence_name          = connection.default_sequence_name(table_name, primary_key)
      end

      # Specify table columns which should be ignored by ActiveRecord, e.g.:
      # 
      #   ignore_table_columns :attribute1, :attribute2
      def ignore_table_columns(*args)
        connection.ignore_table_columns(table_name,*args)
      end

      # Specify which table columns should be typecasted to Date (without time), e.g.:
      # 
      #   set_date_columns :created_on, :updated_on
      def set_date_columns(*args)
        connection.set_type_for_columns(table_name,:date,*args)
      end

      # Specify which table columns should be typecasted to Time (or DateTime), e.g.:
      # 
      #   set_datetime_columns :created_date, :updated_date
      def set_datetime_columns(*args)
        connection.set_type_for_columns(table_name,:datetime,*args)
      end

      # Specify which table columns should be typecasted to boolean values +true+ or +false+, e.g.:
      # 
      #   set_boolean_columns :is_valid, :is_completed
      def set_boolean_columns(*args)
        connection.set_type_for_columns(table_name,:boolean,*args)
      end

      # Specify which table columns should be typecasted to integer values.
      # Might be useful to force NUMBER(1) column to be integer and not boolean, or force NUMBER column without
      # scale to be retrieved as integer and not decimal. Example:
      # 
      #   set_integer_columns :version_number, :object_identifier
      def set_integer_columns(*args)
        connection.set_type_for_columns(table_name,:integer,*args)
      end

      # Specify which table columns should be typecasted to string values.
      # Might be useful to specify that columns should be string even if its name matches boolean column criteria.
      # 
      #   set_string_columns :active_flag
      def set_string_columns(*args)
        connection.set_type_for_columns(table_name,:string,*args)
      end

      # Get table comment from schema definition.
      def table_comment
        connection.table_comment(self.table_name)
      end

      def virtual_columns
        columns.select do |column|
          column.respond_to?(:virtual?) && column.virtual?
        end
      end
    end

    def self.included(base)
      base.class_eval do
        extend ClassMethods
      end
    end

    def arel_attributes_with_values(attribute_names)
      virtual_column_names = self.class.virtual_columns.map(&:name)
      super(attribute_names - virtual_column_names)
    end

    private

    # After setting large objects to empty, select the OCI8::LOB
    # and write back the data.
    def update
      super
      if connection.is_a?(ConnectionAdapters::OracleEnhancedAdapter) &&
          !(
            (self.class.respond_to?(:custom_create_method) && self.class.custom_create_method) ||
            (self.class.respond_to?(:custom_update_method) && self.class.custom_update_method)
          )
        connection.write_lobs(self.class.table_name, self.class, attributes)
      end
    end
  end
end
