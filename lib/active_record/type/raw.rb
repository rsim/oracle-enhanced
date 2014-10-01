require 'active_record/type/string'
 
module ActiveRecord
  module Type
    class Raw < String # :nodoc:
      def type
        :raw
      end
    end
  end
end
