# frozen_string_literal: true

require_relative "oracle_common"

module Arel # :nodoc: all
  module Visitors
    class Oracle12 < Arel::Visitors::ToSql
      include OracleCommon

      private
        # Oracle raises ORA-02014 when `FETCH FIRST n ROWS ONLY` is combined
        # with `FOR UPDATE`. When a limit is present alongside a lock, delegate
        # the whole SELECT to Arel::Visitors::Oracle, whose ROWNUM-based output
        # is compatible with FOR UPDATE for the simple case and surfaces any
        # remaining ORA-02014 as a regular StatementInvalid for compound cases
        # (ORDER BY / GROUP BY / HAVING / OFFSET / DISTINCT) instead of raising
        # an ArgumentError from an internal visitor that callers cannot avoid.
        def visit_Arel_Nodes_SelectStatement(o, collector)
          if o.limit && o.lock
            # Arel::Visitors::Oracle's simple-limit branch mutates `o.cores`
            # by pushing a ROWNUM predicate into the WHERE list. dup the node
            # so a re-compile of the same statement does not accumulate
            # `ROWNUM <= n AND ROWNUM <= n AND ...` predicates.
            return oracle11_visitor.accept(o.dup, collector)
          end
          o = order_hacks(o)
          super
        end

        def oracle11_visitor
          @oracle11_visitor ||= Arel::Visitors::Oracle.new(@connection)
        end

        def visit_Arel_Nodes_SelectOptions(o, collector)
          collector = maybe_visit o.offset, collector
          collector = maybe_visit o.limit, collector
          maybe_visit o.lock, collector
        end

        def visit_Arel_Nodes_Limit(o, collector)
          collector << "FETCH FIRST "
          collector = visit o.expr, collector
          collector << " ROWS ONLY"
        end

        def visit_Arel_Nodes_Offset(o, collector)
          collector << "OFFSET "
          visit o.expr, collector
          collector << " ROWS"
        end

        def visit_Arel_Nodes_Except(o, collector)
          collector << "( "
          collector = infix_value o, collector, " MINUS "
          collector << " )"
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

        def is_distinct_from(o, collector)
          collector << "DECODE("
          collector = visit [o.left, o.right, 0, 1], collector
          collector << ")"
        end

        # Oracle will occur an error `ORA-00907: missing right parenthesis`
        # when using `ORDER BY` in `UPDATE` or `DELETE`'s subquery.
        #
        # This method has been overridden based on the following code.
        # https://github.com/rails/rails/blob/v6.1.0.rc1/activerecord/lib/arel/visitors/to_sql.rb#L815-L825
        def build_subselect(key, o)
          stmt             = super
          stmt.orders      = [] # `orders` will never be set to prevent `ORA-00907`.
          stmt
        end
    end
  end
end
