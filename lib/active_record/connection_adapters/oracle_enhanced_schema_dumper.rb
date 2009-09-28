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
        @connection.tables.sort.each do |tbl|
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
          table(tbl, stream)
          # add primary key trigger if table has it
          primary_key_trigger(tbl, stream)
          # add foreign keys if table has them
          foreign_keys(tbl, stream)
        end
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
        if (foreign_keys = @connection.foreign_keys(table_name)).any?
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
            if foreign_key.options[:dependent].present?
              statement_parts << (':dependent => ' + foreign_key.options[:dependent].inspect)
            end

            '  ' + statement_parts.join(', ')
          end

          stream.puts add_foreign_key_statements.sort.join("\n")
          stream.puts
        end
      end

      def synonyms(stream)
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

      def indexes_with_oracle_enhanced(table, stream)
        if (indexes = @connection.indexes(table)).any?
          add_index_statements = indexes.map do |index|
            # use table.inspect as it will remove prefix and suffix
            statment_parts = [ ('add_index ' + table.inspect) ]
            statment_parts << index.columns.inspect
            statment_parts << (':name => ' + index.name.inspect)
            statment_parts << ':unique => true' if index.unique

            '  ' + statment_parts.join(', ')
          end

          stream.puts add_index_statements.sort.join("\n")
          stream.puts
        end
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
