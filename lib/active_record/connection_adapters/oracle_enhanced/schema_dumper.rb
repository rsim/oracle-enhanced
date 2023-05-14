# frozen_string_literal: true

module ActiveRecord # :nodoc:
  module ConnectionAdapters # :nodoc:
    module OracleEnhanced # :nodoc:
      class SchemaDumper < ConnectionAdapters::SchemaDumper # :nodoc:
        DEFAULT_PRIMARY_KEY_COLUMN_SPEC = { precision: "38", null: "false" }.freeze
        private_constant :DEFAULT_PRIMARY_KEY_COLUMN_SPEC

        private
          def column_spec_for_primary_key(column)
            spec = super
            spec.except!(:precision) if prepare_column_options(column) == DEFAULT_PRIMARY_KEY_COLUMN_SPEC
            spec
          end

          def tables(stream)
            # do not include materialized views in schema dump - they should be created separately after schema creation
            sorted_tables = (@connection.tables - @connection.materialized_views).sort
            sorted_tables.each do |tbl|
              # add table prefix or suffix for schema_migrations
              next if ignored? tbl
              table(tbl, stream)
            end
            # following table definitions
            # add foreign keys if table has them
            sorted_tables.each do |tbl|
              next if ignored? tbl
              foreign_keys(tbl, stream)
            end

            # add synonyms in local schema
            synonyms(stream)
          end

          def synonyms(stream)
            syns = @connection.synonyms
            syns.each do |syn|
              next if ignored? syn.name
              table_name = syn.table_name
              table_name = "#{syn.table_owner}.#{table_name}" if syn.table_owner
              stream.print "  add_synonym #{syn.name.inspect}, #{table_name.inspect}, force: true"
              stream.puts
            end
            stream.puts unless syns.empty?
          end

          def _indexes(table, stream)
            if (indexes = @connection.indexes(table)).any?
              add_index_statements = indexes.filter_map do |index|
                case index.type
                when nil
                  # do nothing here. see indexes_in_create
                  statement_parts = []
                when "CTXSYS.CONTEXT"
                  if index.statement_parameters
                    statement_parts = [ ("add_context_index " + remove_prefix_and_suffix(table).inspect) ]
                    statement_parts << index.statement_parameters
                  else
                    statement_parts = [ ("add_context_index " + remove_prefix_and_suffix(table).inspect) ]
                    statement_parts << index.columns.inspect
                    statement_parts << ("sync: " + $1.inspect) if index.parameters =~ /SYNC\((.*?)\)/
                    statement_parts << ("name: " + index.name.inspect)
                  end
                else
                  # unrecognized index type
                  statement_parts = ["# unrecognized index #{index.name.inspect} with type #{index.type.inspect}"]
                end
                "  " + statement_parts.join(", ") unless statement_parts.empty?
              end

              return if add_index_statements.empty?

              stream.puts add_index_statements.sort.join("\n")
              stream.puts
            end
          end

          def indexes_in_create(table, stream)
            if (indexes = @connection.indexes(table)).any?
              index_statements = indexes.map do |index|
                "    t.index #{index_parts(index).join(', ')}" unless index.type == "CTXSYS.CONTEXT"
              end
              stream.puts index_statements.compact.sort.join("\n")
            end
          end

          def index_parts(index)
            index_parts = super
            index_parts << "tablespace: #{index.tablespace.inspect}" if index.tablespace
            index_parts
          end

          def table(table, stream)
            columns = @connection.columns(table)
            begin
              self.table_name = table

              tbl = StringIO.new

              # first dump primary key column
              if @connection.respond_to?(:primary_keys)
                pk = @connection.primary_keys(table)
                pk = pk.first unless pk.size > 1
              else
                pk = @connection.primary_key(table)
              end

              tbl.print "  create_table #{remove_prefix_and_suffix(table).inspect}"

              # addition to make temporary option work
              tbl.print ", temporary: true" if @connection.temporary_table?(table)

              case pk
              when String
                tbl.print ", primary_key: #{pk.inspect}" unless pk == "id"
                pkcol = columns.detect { |c| c.name == pk }
                pkcolspec = column_spec_for_primary_key(pkcol)
                unless pkcolspec.empty?
                  if pkcolspec != pkcolspec.slice(:id, :default)
                    pkcolspec = { id: { type: pkcolspec.delete(:id), **pkcolspec }.compact }
                  end
                  tbl.print ", #{format_colspec(pkcolspec)}"
                end
              when Array
                tbl.print ", primary_key: #{pk.inspect}"
              else
                tbl.print ", id: false"
              end

              table_options = @connection.table_options(table)
              if table_options.present?
                tbl.print ", #{format_options(table_options)}"
              end

              tbl.puts ", force: :cascade do |t|"

              # then dump all non-primary key columns
              columns.each do |column|
                raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" unless @connection.valid_type?(column.type)
                next if column.name == pk
                type, colspec = column_spec(column)
                tbl.print "    t.#{type} #{column.name.inspect}"
                tbl.print ", #{format_colspec(colspec)}" if colspec.present?
                tbl.puts
              end

              indexes_in_create(table, tbl)

              tbl.puts "  end"
              tbl.puts

              _indexes(table, tbl)

              tbl.rewind
              stream.print tbl.read
            rescue => e
              stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
              stream.puts "#   #{e.message}"
              stream.puts
            ensure
              self.table_name = nil
            end
          end

          def prepare_column_options(column)
            spec = super

            if @connection.supports_virtual_columns? && column.virtual?
              spec[:as] = extract_expression_for_virtual_column(column)
              spec = { type: schema_type(column).inspect }.merge!(spec) unless column.type == :decimal
            end

            spec
          end

          def default_primary_key?(column)
            schema_type(column) == :integer
          end

          def extract_expression_for_virtual_column(column)
            column_name = column.name
            @connection.select_value(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name.upcase), bind_string("column_name", column_name.upcase)]).inspect
              select data_default from all_tab_columns
              where owner = SYS_CONTEXT('userenv', 'current_schema')
              and table_name = :table_name
              and column_name = :column_name
            SQL
          end

          def bind_string(name, value)
            ActiveRecord::Relation::QueryAttribute.new(name, value, Type::OracleEnhanced::String.new)
          end
      end
    end
  end
end
