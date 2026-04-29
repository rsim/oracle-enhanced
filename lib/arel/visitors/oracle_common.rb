# frozen_string_literal: true

module Arel # :nodoc: all
  module Visitors
    module OracleCommon
      BIND_BLOCK = proc { |i| ":a#{i}" }
      private_constant :BIND_BLOCK

      def bind_block; BIND_BLOCK; end

      private
        # Oracle can't compare CLOB columns with standard SQL operators for comparison.
        # We need to replace standard equality for text/binary columns to use DBMS_LOB.COMPARE function.
        # Fixes ORA-00932: inconsistent datatypes: expected - got CLOB
        def visit_Arel_Nodes_Equality(o, collector)
          left = o.left
          return super unless %i(text binary).include?(cached_column_for(left)&.type)

          # https://docs.oracle.com/cd/B19306_01/appdev.102/b14258/d_lob.htm#i1016668
          # returns 0 when the comparison succeeds
          comparator = Arel::Nodes::NamedFunction.new("DBMS_LOB.COMPARE", [left, o.right])
          collector = visit comparator, collector
          collector << " = 0"
          collector
        end

        def visit_Arel_Nodes_Matches(o, collector)
          if !o.case_sensitive && o.left && o.right
            o.left = Arel::Nodes::NamedFunction.new("UPPER", [o.left])
            o.right = Arel::Nodes::NamedFunction.new("UPPER", [o.right])
          end

          super o, collector
        end

        def cached_column_for(attr)
          return unless Arel::Attributes::Attribute === attr

          table = attr.relation.name
          return unless schema_cache.columns_hash?(table)

          column = attr.name.to_s
          schema_cache.columns_hash(table)[column]
        end

        def schema_cache
          @connection.schema_cache
        end

        def visit_Arel_Nodes_In(o, collector)
          attr, values = o.left, o.right
          return super unless values.is_a?(Array)

          in_clause_length = @connection.in_clause_length
          return super if values.length <= in_clause_length

          # Split into multiple IN nodes and combine with OR
          in_nodes = values.each_slice(in_clause_length).map do |slice|
            Arel::Nodes::In.new(attr, slice)
          end
          or_node = Arel::Nodes::Or.new(in_nodes)
          visit(Arel::Nodes::Grouping.new(or_node), collector)
        end

        def visit_Arel_Nodes_NotIn(o, collector)
          attr, values = o.left, o.right
          return super unless values.is_a?(Array)

          in_clause_length = @connection.in_clause_length
          return super if values.length <= in_clause_length

          # Split into multiple NOT IN nodes and combine with AND
          not_in_nodes = values.each_slice(in_clause_length).map do |slice|
            Arel::Nodes::NotIn.new(attr, slice)
          end
          visit(Arel::Nodes::And.new(not_in_nodes), collector)
        end
    end
  end
end
