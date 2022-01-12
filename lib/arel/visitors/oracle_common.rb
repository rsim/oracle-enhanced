# frozen_string_literal: true

module Arel # :nodoc: all
  module Visitors
    module OracleCommon
      private
        def visit_Arel_Nodes_Matches(o, collector)
          if !o.case_sensitive && o.left && o.right
            o.left = Arel::Nodes::NamedFunction.new("UPPER", [o.left])
            o.right = Arel::Nodes::NamedFunction.new("UPPER", [o.right])
          end

          super o, collector
        end
    end
  end
end
