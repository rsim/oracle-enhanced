module ActiveRecord
  module Type
    class Timestamp < Value # :nodoc:
      def type
        :timestamp
      end
    end
  end
end
