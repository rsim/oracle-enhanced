module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedCpk #:nodoc:

      # This mightn't be in Core, but count(distinct x,y) doesn't work for me
      def supports_count_distinct? #:nodoc:
        false
      end
      
      def concat(*columns)
        "(#{columns.join('||')})"
      end
      
    end
  end
end

ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
  include ActiveRecord::ConnectionAdapters::OracleEnhancedCpk
end
