require 'active_model/type/string'

#TODO Need to consider namespace change since paremt class moved to ActiveModel
module ActiveRecord
  module OracleEnhanced
    module Type
      class Raw < ActiveModel::Type::String # :nodoc:
        def type
          :raw
        end
      end
    end
  end
end
