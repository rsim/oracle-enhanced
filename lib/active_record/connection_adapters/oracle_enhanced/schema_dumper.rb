module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhanced #:nodoc:
      module SchemaDumper #:nodoc:

        private

        def tables(stream)
          return super unless @connection.respond_to?(:materialized_views)
          # do not include materialized views in schema dump - they should be created separately after schema creation
          sorted_tables = (@connection.data_sources - @connection.materialized_views).sort
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
            stream.print ", primary_key: \"#{pk}\"" if pk != 'id'
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
                # use table.inspect as it will remove prefix and suffix
                statement_parts = [ ('add_index ' + table.inspect) ]
                statement_parts << index.columns.inspect
                statement_parts << ('name: ' + index.name.inspect)
                statement_parts << 'unique: true' if index.unique
                statement_parts << 'tablespace: ' + index.tablespace.inspect if index.tablespace
              when 'CTXSYS.CONTEXT'
                if index.statement_parameters
                  statement_parts = [ ('add_context_index ' + table.inspect) ]
                  statement_parts << index.statement_parameters
                else
                  statement_parts = [ ('add_context_index ' + table.inspect) ]
                  statement_parts << index.columns.inspect
                  statement_parts << ('name: ' + index.name.inspect)
                end
              else
                # unrecognized index type
                statement_parts = ["# unrecognized index #{index.name.inspect} with type #{index.type.inspect}"]
              end
              '  ' + statement_parts.join(', ')
            end

            stream.puts add_index_statements.sort.join("\n")
            stream.puts
          end
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

            table_comments = @connection.table_comment(table)
            unless table_comments.nil?
              tbl.print ", comment: #{table_comments.inspect}"
            end

            case pk
            when String
              tbl.print ", primary_key: #{pk.inspect}" unless pk == 'id'
              pkcol = columns.detect { |c| c.name == pk }
              pkcolspec = @connection.column_spec_for_primary_key(pkcol)
              if pkcolspec.present?
                pkcolspec.each do |key, value|
                  tbl.print ", #{key}: #{value}"
                end
              end
            when Array
              tbl.print ", primary_key: #{pk.inspect}"
            else
              tbl.print ", id: false"
            end

            tbl.print ", force: :cascade"
            tbl.puts " do |t|"

            # then dump all non-primary key columns
            column_specs = columns.map do |column|
              raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" unless @connection.valid_type?(column.type)
              next if column.name == pk
              @connection.column_spec(column)
            end.compact

            # find all migration keys used in this table
            #
            # TODO `& column_specs.map(&:keys).flatten` should be executed
            # in migration_keys_with_oracle_enhanced
            keys = @connection.migration_keys & column_specs.map(&:keys).flatten

            # figure out the lengths for each column based on above keys
            lengths = keys.map{ |key| column_specs.map{ |spec| spec[key] ? spec[key].length + 2 : 0 }.max }

            # the string we're going to sprintf our values against, with standardized column widths
            format_string = lengths.map{ |len| "%-#{len}s" }

            # find the max length for the 'type' column, which is special
            type_length = column_specs.map{ |column| column[:type].length }.max

            # add column type definition to our format string
            format_string.unshift "    t.%-#{type_length}s "

            format_string *= ''

            # dirty hack to replace virtual_type: with type:
            column_specs.each do |colspec|
              values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
              values.unshift colspec[:type]
              tbl.print((format_string % values).gsub(/,\s*$/, '').gsub(/virtual_type:/, "type:"))
              tbl.puts
            end

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
            if table_name =~ /\A#{ActiveRecord::Base.table_name_prefix.to_s.gsub('$','\$')}(.*)#{ActiveRecord::Base.table_name_suffix.to_s.gsub('$','\$')}\Z/
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
