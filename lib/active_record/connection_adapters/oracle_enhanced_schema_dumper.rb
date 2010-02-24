module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedSchemaDumper #:nodoc:

      def self.included(base) #:nodoc:
        base.class_eval do
          private
          alias_method_chain :tables, :oracle_enhanced
          alias_method_chain :indexes, :oracle_enhanced
        end
      end

      private
      
      def tables_with_oracle_enhanced(stream)
        sorted_tables = @connection.tables.sort
        sorted_tables.each do |tbl|
          # add table prefix or suffix for schema_migrations
          next if [ActiveRecord::Migrator.proper_table_name('schema_migrations'), ignore_tables].flatten.any? do |ignored|
            case ignored
            when String; tbl == ignored
            when Regexp; tbl =~ ignored
            else
              raise StandardError, 'ActiveRecord::SchemaDumper.ignore_tables accepts an array of String and / or Regexp values.'
            end
          end
          # change table name inspect method
          tbl.extend TableInspect
          oracle_enhanced_table(tbl, stream)
          # add primary key trigger if table has it
          primary_key_trigger(tbl, stream)
        end
        sorted_tables.each do |tbl|
          # add foreign keys if table has them
          foreign_keys(tbl, stream)
        end
        # add synonyms in local schema
        synonyms(stream)
      end

      def primary_key_trigger(table_name, stream)
        if @connection.respond_to?(:has_primary_key_trigger?) && @connection.has_primary_key_trigger?(table_name)
          pk, pk_seq = @connection.pk_and_sequence_for(table_name)
          stream.print "  add_primary_key_trigger #{table_name.inspect}"
          stream.print ", :primary_key => \"#{pk}\"" if pk != 'id'
          stream.print "\n\n"
        end
      end

      def foreign_keys(table_name, stream)
        if @connection.respond_to?(:foreign_keys) && (foreign_keys = @connection.foreign_keys(table_name)).any?
          add_foreign_key_statements = foreign_keys.map do |foreign_key|
            statement_parts = [ ('add_foreign_key ' + foreign_key.from_table.inspect) ]
            statement_parts << foreign_key.to_table.inspect
            statement_parts << (':name => ' + foreign_key.options[:name].inspect)
            
            if foreign_key.options[:column] != "#{foreign_key.to_table.singularize}_id"
              statement_parts << (':column => ' + foreign_key.options[:column].inspect)
            end
            if foreign_key.options[:primary_key] != 'id'
              statement_parts << (':primary_key => ' + foreign_key.options[:primary_key].inspect)
            end
            unless foreign_key.options[:dependent].blank?
              statement_parts << (':dependent => ' + foreign_key.options[:dependent].inspect)
            end

            '  ' + statement_parts.join(', ')
          end

          stream.puts add_foreign_key_statements.sort.join("\n")
          stream.puts
        end
      end

      def synonyms(stream)
        if @connection.respond_to?(:synonyms)
          syns = @connection.synonyms
          syns.each do |syn|
            table_name = syn.table_name
            table_name = "#{syn.table_owner}.#{table_name}" if syn.table_owner
            table_name = "#{table_name}@#{syn.db_link}" if syn.db_link
            stream.print "  add_synonym #{syn.name.inspect}, #{table_name.inspect}, :force => true"
            stream.puts
          end
          stream.puts unless syns.empty?
        end
      end

      def indexes_with_oracle_enhanced(table, stream)
        if (indexes = @connection.indexes(table)).any?
          add_index_statements = indexes.map do |index|
            # use table.inspect as it will remove prefix and suffix
            statment_parts = [ ('add_index ' + table.inspect) ]
            statment_parts << index.columns.inspect
            statment_parts << (':name => ' + index.name.inspect)
            statment_parts << ':unique => true' if index.unique
            statment_parts << ':tablespace => ' + index.tablespace.inspect if index.tablespace

            '  ' + statment_parts.join(', ')
          end

          stream.puts add_index_statements.sort.join("\n")
          stream.puts
        end
      end

      def oracle_enhanced_table(table, stream)
        columns = @connection.columns(table)
        begin
          tbl = StringIO.new

          # first dump primary key column
          if @connection.respond_to?(:pk_and_sequence_for)
            pk, pk_seq = @connection.pk_and_sequence_for(table)
          elsif @connection.respond_to?(:primary_key)
            pk = @connection.primary_key(table)
          end
          
          tbl.print "  create_table #{table.inspect}"
          
          # addition to make temporary option work
          tbl.print ", :temporary => true" if @connection.temporary_table?(table)
          
          if columns.detect { |c| c.name == pk }
            if pk != 'id'
              tbl.print %Q(, :primary_key => "#{pk}")
            end
          else
            tbl.print ", :id => false"
          end
          tbl.print ", :force => true"
          tbl.puts " do |t|"

          # then dump all non-primary key columns
          column_specs = columns.map do |column|
            raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" if @types[column.type].nil?
            next if column.name == pk
            spec = {}
            spec[:name]      = column.name.inspect
            spec[:type]      = column.type.to_s
            spec[:limit]     = column.limit.inspect if column.limit != @types[column.type][:limit] && column.type != :decimal
            spec[:precision] = column.precision.inspect if !column.precision.nil?
            spec[:scale]     = column.scale.inspect if !column.scale.nil?
            spec[:null]      = 'false' if !column.null
            spec[:default]   = default_string(column.default) if column.has_default?
            (spec.keys - [:name, :type]).each{ |k| spec[k].insert(0, "#{k.inspect} => ")}
            spec
          end.compact

          # find all migration keys used in this table
          keys = [:name, :limit, :precision, :scale, :default, :null] & column_specs.map(&:keys).flatten

          # figure out the lengths for each column based on above keys
          lengths = keys.map{ |key| column_specs.map{ |spec| spec[key] ? spec[key].length + 2 : 0 }.max }

          # the string we're going to sprintf our values against, with standardized column widths
          format_string = lengths.map{ |len| "%-#{len}s" }

          # find the max length for the 'type' column, which is special
          type_length = column_specs.map{ |column| column[:type].length }.max

          # add column type definition to our format string
          format_string.unshift "    t.%-#{type_length}s "

          format_string *= ''

          column_specs.each do |colspec|
            values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
            values.unshift colspec[:type]
            tbl.print((format_string % values).gsub(/,\s*$/, ''))
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
      
      
      # remove table name prefix and suffix when doing #inspect (which is used in tables method)
      module TableInspect #:nodoc:
        def inspect
          remove_prefix_and_suffix(self)
        end
        
        private
        def remove_prefix_and_suffix(table_name)
          if table_name =~ /\A#{ActiveRecord::Base.table_name_prefix}(.*)#{ActiveRecord::Base.table_name_suffix}\Z/
            "\"#{$1}\""
          else
            "\"#{table_name}\""
          end
        end
      end

    end
  end
end

ActiveRecord::SchemaDumper.class_eval do
  include ActiveRecord::ConnectionAdapters::OracleEnhancedSchemaDumper
end
