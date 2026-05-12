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
    end
  end
end
