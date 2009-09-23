module ActiveRecord #:nodoc:
  module ConnectionAdapters #:nodoc:
    module OracleEnhancedSchemaDumper #:nodoc:

      def self.included(base)
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
          # next if ['schema_migrations', ignore_tables].flatten.any? do |ignored|
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
        end
      end

      def indexes_with_oracle_enhanced(table, stream)
        indexes = @connection.indexes(table)
        indexes.each do |index|
          # use table.inspect as it will remove prefix and suffix
          stream.print "  add_index #{table.inspect}, #{index.columns.inspect}, :name => #{index.name.inspect}"
          stream.print ", :unique => true" if index.unique
          stream.puts
        end
        stream.puts unless indexes.empty?
      end

      # remove table name prefix and suffix when doing #inspect (which is used in tables method)
      module TableInspect
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
