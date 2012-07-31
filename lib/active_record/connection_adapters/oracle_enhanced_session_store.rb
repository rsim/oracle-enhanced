module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedSqlBypass #:nodoc:

      def self.included(base) #:nodoc:
        base.class_eval do
          private
          alias_method_chain :save, :oracle_enhanced
        end
      end
     
      private

      def save_with_oracle_enhanced
        # return original method if not using 'Oracle' nor 'OracleEnhanced'
        return save_without_oracle_enhanced unless connection.adapter_name.index('Oracle') == 0

        return false unless loaded?
        marshaled_data = self.class.marshal(data)
        connect        = connection

        # Insert statement explicitly requires the 'id' column and '#{table_name}_seq.nextval' value.
        if @new_record
          @new_record = false
          connect.update <<-end_sql, 'Create session'
            INSERT INTO #{table_name} (
              id,
              #{connect.quote_column_name(session_id_column)},
              #{connect.quote_column_name(data_column)} )
            VALUES (
              #{table_name}_seq.nextval,
              #{connect.quote(session_id)},
              #{connect.quote(marshaled_data)} )
          end_sql
        else
          connect.update <<-end_sql, 'Update session'
            UPDATE #{table_name}
              SET #{connect.quote_column_name(data_column)}=#{connect.quote(marshaled_data)}
              WHERE #{connect.quote_column_name(session_id_column)}=#{connect.quote(session_id)}
          end_sql
        end
      end
    end
  end
end

ActiveRecord::SessionStore::SqlBypass.class_eval do
  include ActiveRecord::ConnectionAdapters::OracleEnhancedSqlBypass
end
