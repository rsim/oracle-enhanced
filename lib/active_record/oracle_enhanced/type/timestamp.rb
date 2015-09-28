#TODO Need to consider namespace change since paremt class moved to ActiveModel
module ActiveRecord
  module OracleEnhanced
    module Type
      class Timestamp < ActiveModel::Type::Value # :nodoc:
        def type
          :timestamp
        end
      end
    end
  end
end
