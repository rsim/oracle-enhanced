# frozen_string_literal: true

require_relative "oracle_common"

module Arel # :nodoc: all
  module Visitors
    class Oracle < Arel::Visitors::ToSql
      include OracleCommon

      private
        def visit_Arel_Nodes_SelectStatement(o, collector)
          return super(order_hacks(o), collector) unless rownum?(o)
          return rownum_visitor.accept(o, collector) unless @rownum

          visit_select_statement_with_rownum(o, collector) { |stmt, c| super(stmt, c) }
        end

        # A copy of this visitor that writes every SELECT it compiles, including nested ones, with ROWNUM.
        # The flag is set only on the copy, so neither visitor changes state while compiling and both can
        # be used from several threads, as a pinned connection may be.
        def rownum_visitor
          @rownum_visitor ||= dup.tap { |visitor| visitor.instance_variable_set(:@rownum, true) }
        end

        # Oracle before 12.1 has no row limiting clause, so LIMIT and OFFSET are written with ROWNUM.
        # ROWNUM is also used for a limit combined with a lock, because Oracle raises ORA-02014 for
        # FETCH FIRST with FOR UPDATE. A statement nested in one written with ROWNUM uses ROWNUM too.
        def rownum?(o = nil)
          @rownum || (o&.limit && o.lock) || !use_fetch_first_syntax?
        end

        def use_fetch_first_syntax?
          @connection.use_fetch_first_syntax?
        end

        def visit_select_statement_with_rownum(o, collector)
          o = order_hacks(o)

          # if need to select first records without ORDER BY and GROUP BY and without DISTINCT
          # then can use simple ROWNUM in WHERE clause
          if o.limit && o.orders.empty? && o.cores.first.groups.empty? && !o.offset && !o.cores.first.set_quantifier.class.to_s.include?("Distinct")
            o = o.dup
            o.cores.last.wheres.push Nodes::LessThanOrEqual.new(
              Nodes::SqlLiteral.new("ROWNUM", retryable: true), o.limit.expr
            )
            return yield(o, collector)
          end

          if o.limit && o.offset
            o        = o.dup
            limit    = o.limit.expr
            offset   = o.offset
            o.offset = nil
            collector << "
                SELECT * FROM (
                  SELECT raw_sql_.*, rownum raw_rnum_
                  FROM ("

            collector = yield(o, collector)

            if bind_limit_offset?(limit, offset.expr)
              collector << ") raw_sql_ WHERE rownum <= ("
              collector = visit offset.expr, collector
              collector << " + "
              collector = visit limit, collector
              collector << ") ) WHERE raw_rnum_ > "
              collector = visit offset.expr, collector
              return collector
            else
              offset_value = value_before_type_cast(offset.expr)
              limit_value = value_before_type_cast(limit)
              collector << ") raw_sql_
                  WHERE rownum <= #{offset_value + limit_value}
                )
                WHERE "
              return visit(offset, collector)
            end
          end

          if o.limit
            o       = o.dup
            limit   = o.limit.expr
            collector << "SELECT * FROM ("
            collector = yield(o, collector)
            collector << ") WHERE ROWNUM <= "
            return visit limit, collector
          end

          if o.offset
            o        = o.dup
            offset   = o.offset
            o.offset = nil
            collector << "SELECT * FROM (
                  SELECT raw_sql_.*, rownum raw_rnum_
                  FROM ("
            collector = yield(o, collector)
            collector << ") raw_sql_
                )
                WHERE "
            return visit offset, collector
          end

          yield(o, collector)
        end

        def visit_Arel_Nodes_SelectOptions(o, collector)
          return super if rownum?

          collector = maybe_visit o.offset, collector
          collector = maybe_visit o.limit, collector
          maybe_visit o.lock, collector
        end

        def visit_Arel_Nodes_Limit(o, collector)
          return collector if rownum?

          collector << "FETCH FIRST "
          collector = visit o.expr, collector
          collector << " ROWS ONLY"
        end

        def visit_Arel_Nodes_Offset(o, collector)
          if rownum?
            collector << "raw_rnum_ > "
            visit o.expr, collector
          else
            collector << "OFFSET "
            visit o.expr, collector
            collector << " ROWS"
          end
        end

        def visit_Arel_Nodes_Except(o, collector)
          collector << "( "
          collector = infix_value o, collector, " MINUS "
          collector << " )"
        end

        def bind_limit_offset?(limit, offset)
          [limit, offset].any? do |expr|
            expr.is_a?(Arel::Nodes::BindParam) ||
              (expr.respond_to?(:type) && expr.type.is_a?(ActiveModel::Type::Value))
          end
        end

        def value_before_type_cast(expr)
          if expr.respond_to?(:value_before_type_cast)
            expr.value_before_type_cast
          else
            expr
          end
        end

        def is_distinct_from(o, collector)
          collector << "DECODE("
          collector = visit [o.left, o.right, 0, 1], collector
          collector << ")"
        end
    end
  end
end
