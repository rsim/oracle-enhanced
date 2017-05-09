module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module SchemaDumper #:nodoc:
        private

          def tables(stream)
            return super unless @connection.respond_to?(:materialized_views)
            # do not include materialized views in schema dump - they should be created separately after schema creation
            sorted_tables = (@connection.tables - @connection.materialized_views).sort
            sorted_tables.each do |tbl|
              # add table prefix or suffix for schema_migrations
              next if ignored? tbl
              # change table name inspect method
              tbl.extend TableInspect
              table(tbl, stream)
              # add primary key trigger if table has it
              primary_key_trigger(tbl, stream)
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

          def primary_key_trigger(table_name, stream)
            if @connection.respond_to?(:has_primary_key_trigger?) && @connection.has_primary_key_trigger?(table_name)
              pk, _pk_seq = @connection.pk_and_sequence_for(table_name)
              stream.print "  add_primary_key_trigger #{table_name.inspect}"
              stream.print ", primary_key: \"#{pk}\"" if pk != "id"
              stream.print "\n\n"
            end
          end

          def synonyms(stream)
            if @connection.respond_to?(:synonyms)
              syns = @connection.synonyms
              syns.each do |syn|
                next if ignored? syn.name
                table_name = syn.table_name
                table_name = "#{syn.table_owner}.#{table_name}" if syn.table_owner
                table_name = "#{table_name}@#{syn.db_link}" if syn.db_link
                stream.print "  add_synonym #{syn.name.inspect}, #{table_name.inspect}, force: true"
                stream.puts
              end
              stream.puts unless syns.empty?
            end
          end

          def indexes(table, stream)
            if (indexes = @connection.indexes(table)).any?
              add_index_statements = indexes.map do |index|
                case index.type
                when nil
                  # do nothing here. see indexes_in_create
                  statement_parts = []
                when "CTXSYS.CONTEXT"
                  if index.statement_parameters
                    statement_parts = [ ("add_context_index " + table.inspect) ]
                    statement_parts << index.statement_parameters
                  else
                    statement_parts = [ ("add_context_index " + table.inspect) ]
                    statement_parts << index.columns.inspect
                    statement_parts << ("name: " + index.name.inspect)
                  end
                else
                  # unrecognized index type
                  statement_parts = ["# unrecognized index #{index.name.inspect} with type #{index.type.inspect}"]
                end
                "  " + statement_parts.join(", ") unless statement_parts.empty?
              end.compact

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
              stream.puts index_statements.sort.join("\n")
            end
          end

          def index_parts(index)
            return super unless @connection.respond_to?(:temporary_table?)
            index_parts = super
            index_parts << "tablespace: #{index.tablespace.inspect}" if index.tablespace
            index_parts
          end

          def table(table, stream)
            return super unless @connection.respond_to?(:temporary_table?)
            columns = @connection.columns(table)
            begin
              tbl = StringIO.new

              # first dump primary key column
              if @connection.respond_to?(:primary_keys)
                pk = @connection.primary_keys(table)
                pk = pk.first unless pk.size > 1
              else
                pk = @connection.primary_key(table)
              end

              tbl.print "  create_table #{table.inspect}"

              # addition to make temporary option work
              tbl.print ", temporary: true" if @connection.temporary_table?(table)

              case pk
              when String
                tbl.print ", primary_key: #{pk.inspect}" unless pk == "id"
                pkcol = columns.detect { |c| c.name == pk }
                pkcolspec = @connection.column_spec_for_primary_key(pkcol)
                if pkcolspec.present?
                  tbl.print ", #{format_colspec(pkcolspec)}"
                end
              when Array
                tbl.print ", primary_key: #{pk.inspect}"
              else
                tbl.print ", id: false"
              end

              tbl.print ", force: :cascade"

              table_comments = @connection.table_comment(table)
              unless table_comments.blank?
                tbl.print ", comment: #{table_comments.inspect}"
              end

              tbl.puts " do |t|"

              # then dump all non-primary key columns
              columns.each do |column|
                raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" unless @connection.valid_type?(column.type)
                next if column.name == pk
                type, colspec = @connection.column_spec(column)
                tbl.print "    t.#{type} #{column.name.inspect}"
                tbl.print ", #{format_colspec(colspec)}" if colspec.present?
                tbl.puts
              end

              indexes_in_create(table, tbl)

              tbl.puts "  end"
              tbl.puts

              indexes(table, tbl)

              tbl.rewind
              stream.print tbl.read
            rescue => e
              stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
              stream.puts "#   #{e.message}"
              stream.puts
            end

            stream
          end

          def remove_prefix_and_suffix(table)
            table.gsub(/^(#{ActiveRecord::Base.table_name_prefix})(.+)(#{ActiveRecord::Base.table_name_suffix})$/,  "\\2")
          end

          # remove table name prefix and suffix when doing #inspect (which is used in tables method)
          module TableInspect #:nodoc:
            def inspect
              remove_prefix_and_suffix(self)
            end

            private
              def remove_prefix_and_suffix(table_name)
                if table_name =~ /\A#{ActiveRecord::Base.table_name_prefix.to_s.gsub('$', '\$')}(.*)#{ActiveRecord::Base.table_name_suffix.to_s.gsub('$', '\$')}\Z/
                  "\"#{$1}\""
                else
                  "\"#{table_name}\""
                end
              end
          end
      end
    end
  end

  class SchemaDumper #:nodoc:
    prepend ConnectionAdapters::OracleEnhanced::SchemaDumper
  end
end
