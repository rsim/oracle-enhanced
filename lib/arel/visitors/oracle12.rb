# frozen_string_literal: true

require_relative "oracle_common"

module Arel # :nodoc: all
  module Visitors
    class Oracle12 < Arel::Visitors::ToSql
      include OracleCommon

      private
        # Delegate the whole SELECT to Arel::Visitors::Oracle (ROWNUM-based
        # LIMIT/OFFSET) in two cases:
        #
        # * The server is older than 12.1 and has no FETCH FIRST. This is how
        #   `arel_visitor: :auto` follows the server version: the check runs
        #   when SQL is compiled, so the adapter picks this visitor without a
        #   connection. The version is cached per connection pool.
        # * Oracle raises ORA-02014 when `FETCH FIRST n ROWS ONLY` is combined
        #   with `FOR UPDATE`. When a limit is present alongside a lock, the
        #   ROWNUM-based output is compatible with FOR UPDATE for the simple
        #   case and surfaces any remaining ORA-02014 as a regular
        #   StatementInvalid for compound cases (ORDER BY / GROUP BY / HAVING /
        #   OFFSET / DISTINCT) instead of raising an ArgumentError from an
        #   internal visitor that callers cannot avoid.
        def visit_Arel_Nodes_SelectStatement(o, collector)
          if (o.limit && o.lock) || !@connection.supports_fetch_first_n_rows_and_offset?
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

        def is_distinct_from(o, collector)
          collector << "DECODE("
          collector = visit [o.left, o.right, 0, 1], collector
          collector << ")"
        end
    end
  end
end
