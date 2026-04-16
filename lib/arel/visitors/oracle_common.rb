# frozen_string_literal: true

module Arel # :nodoc: all
  module Visitors
    module OracleCommon
      BIND_BLOCK = proc { |i| ":a#{i}" }
      private_constant :BIND_BLOCK

      def bind_block; BIND_BLOCK; end

      private
        # Oracle db link tables use "table@link" syntax, but the "@link" part must only
        # appear on table references, not on column qualifiers like table@link.column.
        # Column qualifiers use just the table name (which Oracle resolves as the implicit
        # alias for the remote table). Override Arel's table visitor to emit the "@link"
        # suffix when generating table references, not column qualifiers.
        def visit_Arel_Table(o, collector)
          name = o.name.to_s
          table_part, link = name.split("@", 2)
          quoted_name = link ? "#{@connection.quote_table_name(table_part)}@#{link}" : @connection.quote_table_name(name)

          if o.table_alias
            collector << quoted_name + " " + @connection.quote_table_name(o.table_alias)
          else
            collector << quoted_name
          end
        end

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
    end
  end
end
