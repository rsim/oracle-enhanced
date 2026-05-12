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

        # Oracle 12c+ (Oracle12 visitor) and pre-12c (Oracle visitor) both
        # generate `FIRST_VALUE(...) OVER (...) AS alias_N__` projections via
        # `columns_for_distinct` for DISTINCT queries that order by columns
        # outside the SELECT list. Oracle's own SQL parser then rejects an
        # outer ORDER BY referencing the original (non-aliased) column with
        # ORA-01791 ("not a SELECTed expression"). Rewriting the outer ORDER
        # BY to reference `alias_N__` instead is what makes the SQL valid.
        def order_hacks(o)
          return o if o.orders.empty?
          return o unless o.cores.any? do |core|
            core.projections.any? do |projection|
              projection.to_s.include?("FIRST_VALUE")
            end
          end
          orders = o.orders.map do |x|
            string = visit(x, Arel::Collectors::SQLString.new).value
            if string.include?(",")
              split_order_string(string)
            else
              string
            end
          end.flatten
          o.orders = []
          orders.each_with_index do |order, i|
            parts = ["alias_#{i}__"]
            parts << "DESC" if /\bdesc\b/i.match?(order)
            if (nulls_match = order.match(/\bNULLS\s+(FIRST|LAST)\b/i))
              parts << "NULLS #{nulls_match[1].upcase}"
            end
            o.orders << Arel::Nodes::SqlLiteral.new(parts.join(" "), retryable: true)
          end
          o
        end

        # Split string by commas but count opening and closing brackets
        # and ignore commas inside brackets.
        def split_order_string(string)
          array = []
          i = 0
          string.split(",").each do |part|
            if array[i]
              array[i] << "," << part
            else
              # to ensure that array[i] will be String and not Arel::Nodes::SqlLiteral
              array[i] = part.to_s
            end
            i += 1 if array[i].count("(") == array[i].count(")")
          end
          array
        end

        # To avoid ORA-01795: maximum number of expressions in a list is 1000
        # tell ActiveRecord to limit us to 1000 ids at a time
        def visit_Arel_Nodes_HomogeneousIn(o, collector)
          collector.preparable = false
          in_clause_length = @connection.in_clause_length
          values = o.casted_values.map { |v| @connection.quote(v) }
          operator =
            if o.type == :in
              " IN ("
            else
              " NOT IN ("
            end

          if values.length <= in_clause_length
            visit o.left, collector
            collector << operator

            expr =
              if values.empty?
                @connection.quote(nil)
              else
                values.join(",")
              end

            collector << expr
            collector << ")"
          else
            separator =
              if o.type == :in
                " OR "
              else
                " AND "
              end
            collector << "("
            values.each_slice(in_clause_length).each_with_index do |valuez, i|
              collector << separator unless i == 0
              visit o.left, collector
              collector << operator
              collector << valuez.join(",")
              collector << ")"
            end
            collector << ")"
          end

          collector
        end

        def visit_Arel_Nodes_UpdateStatement(o, collector)
          # Oracle does not allow ORDER BY/LIMIT in UPDATEs.
          if o.orders.any? && o.limit.nil?
            # However, there is no harm in silently eating the ORDER BY clause if no LIMIT has been provided,
            # otherwise let the user deal with the error
            o = o.dup
            o.orders = []
          end

          super
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
