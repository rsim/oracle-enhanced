# frozen_string_literal: true

require_relative "oracle_common"

module Arel # :nodoc: all
  module Visitors
    class Oracle < Arel::Visitors::ToSql
      include OracleCommon

      private
        def visit_Arel_Nodes_SelectStatement(o, collector)
          o = order_hacks(o)

          # if need to select first records without ORDER BY and GROUP BY and without DISTINCT
          # then can use simple ROWNUM in WHERE clause
          if o.limit && o.orders.empty? && o.cores.first.groups.empty? && !o.offset && !o.cores.first.set_quantifier.class.to_s.include?("Distinct")
            o.cores.last.wheres.push Nodes::LessThanOrEqual.new(
              Nodes::SqlLiteral.new("ROWNUM", retryable: true), o.limit.expr
            )
            return super
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

            collector = super(o, collector)

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
            collector = super(o, collector)
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
            collector = super(o, collector)
            collector << ") raw_sql_
                )
                WHERE "
            return visit offset, collector
          end

          super
        end

        def visit_Arel_Nodes_Limit(o, collector)
          collector
        end

        def visit_Arel_Nodes_Offset(o, collector)
          collector << "raw_rnum_ > "
          visit o.expr, collector
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
