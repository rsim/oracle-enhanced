module ActiveRecord
  module ConnectionAdapters #:nodoc:
    class OracleEnhancedColumn < Column

      attr_reader :table_name, :nchar, :virtual_column_data_default, :returning_id #:nodoc:

      def initialize(name, default, sql_type_metadata = nil, null = true, table_name = nil, virtual = false, returning_id = nil, comment = nil) #:nodoc:

        @virtual = virtual
        @virtual_column_data_default = default.inspect if virtual
        @returning_id = returning_id
        if virtual
          default_value = nil
        else
          default_value = self.class.extract_value_from_default(default)
        end
        super(name, default_value, sql_type_metadata, null, table_name, comment: comment)
        # Is column NCHAR or NVARCHAR2 (will need to use N'...' value quoting for these data types)?
        # Define only when needed as adapter "quote" method will check at first if instance variable is defined.
        if sql_type_metadata
          @object_type = sql_type_metadata.sql_type.include? '.'
        end
        # TODO: Need to investigate when `sql_type` becomes nil
      end

      def virtual?
        @virtual
      end

      def returning_id?
        @returning_id
      end

      def lob?
        self.sql_type =~ /LOB$/i
      end

      def object_type?
        @object_type
      end

      # convert something to a boolean
      # added y as boolean value
      def self.value_to_boolean(value) #:nodoc:
        if value == true || value == false
          value
        elsif value.is_a?(String) && value.blank?
          nil
        else
          %w(true t 1 y +).include?(value.to_s.downcase)
        end
      end

      # convert Time or DateTime value to Date for :date columns
      def self.string_to_date(string) #:nodoc:
        return string.to_date if string.is_a?(Time) || string.is_a?(DateTime)
        super
      end

      # convert Date value to Time for :datetime columns
      def self.string_to_time(string) #:nodoc:
        return string.to_time if string.is_a?(Date) && !OracleEnhancedAdapter.emulate_dates
        super
      end

      # Get column comment from schema definition.
      # Will work only if using default ActiveRecord connection.
#      def comment
#        #TODO: may be deprecated due to conflict with variable
#        ActiveRecord::Base.connection.column_comment(@table_name, name)
#      end
      
      private

      def self.extract_value_from_default(default)
        case default
          when String
            default.gsub(/''/, "'")
          else
            default
        end
      end

      def guess_date_or_time(value)
        value.respond_to?(:hour) && (value.hour == 0 and value.min == 0 and value.sec == 0) ?
          Date.new(value.year, value.month, value.day) : value
      end
      
      class << self
        protected

        def fallback_string_to_date(string) #:nodoc:
          if OracleEnhancedAdapter.string_to_date_format || OracleEnhancedAdapter.string_to_time_format
            ActiveSupport::Deprecation.warn(<<-MSG.squish)
              `fallback_string_to_date` has been deprecated.
              It will be removed from next version of Oracle enhanced adapter.
              Users are unlikely to see this message since this method has gone
              from ActiveRecord::ConnectionAdapters::Column in Rails 4.2.
            MSG
            return (string_to_date_or_time_using_format(string).to_date rescue super)
          end
          super
        end

        def fallback_string_to_time(string) #:nodoc:
          if OracleEnhancedAdapter.string_to_time_format || OracleEnhancedAdapter.string_to_date_format
            ActiveSupport::Deprecation.warn(<<-MSG.squish)
              `fallback_string_to_time` has been deprecated.
              It will be removed from next version of Oracle enhanced adapter.
              Users are unlikely to see this message since this method has gone
              from ActiveRecord::ConnectionAdapters::Column in Rails 4.2.
            MSG
            return (string_to_date_or_time_using_format(string).to_time rescue super)
          end
          super
        end

        def string_to_date_or_time_using_format(string) #:nodoc:
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            `string_to_date_or_time_using_format` has been deprecated.
            It will be removed from next version of Oracle enhanced adapter.
            Users are unlikely to see this message since `fallback_string_to_date`
            and `fallback_string_to_time` have gone
            from ActiveRecord::ConnectionAdapters::Column in Rails 4.2.
          MSG
          if OracleEnhancedAdapter.string_to_time_format && dt=Date._strptime(string, OracleEnhancedAdapter.string_to_time_format)
            return Time.parse("#{dt[:year]}-#{dt[:mon]}-#{dt[:mday]} #{dt[:hour]}:#{dt[:min]}:#{dt[:sec]}#{dt[:zone]}")
          end
          DateTime.strptime(string, OracleEnhancedAdapter.string_to_date_format).to_date
        end
        
      end
    end

  end

end
