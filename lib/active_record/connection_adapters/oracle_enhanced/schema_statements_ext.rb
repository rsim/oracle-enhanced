module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module SchemaStatementsExt
        # Add synonym to existing table or view or sequence. Can be used to create local synonym to
        # remote table in other schema or in other database
        # Examples:
        #
        #   add_synonym :posts, "blog.posts"
        #   add_synonym :posts_seq, "blog.posts_seq"
        #   add_synonym :employees, "hr.employees@dblink", :force => true
        #
        def add_synonym(name, table_name, options = {})
          sql = "CREATE"
          if options[:force] == true
            sql << " OR REPLACE"
          end
          sql << " SYNONYM #{quote_table_name(name)} FOR #{quote_table_name(table_name)}"
          execute sql
        end

        # Remove existing synonym to table or view or sequence
        # Example:
        #
        #   remove_synonym :posts, "blog.posts"
        #
        def remove_synonym(name)
          execute "DROP SYNONYM #{quote_table_name(name)}"
        end

        # get synonyms for schema dump
        def synonyms #:nodoc:
          select_all("SELECT synonym_name, table_owner, table_name, db_link FROM all_synonyms where owner = SYS_CONTEXT('userenv', 'session_user')").collect do |row|
            OracleEnhanced::SynonymDefinition.new(oracle_downcase(row["synonym_name"]),
              oracle_downcase(row["table_owner"]), oracle_downcase(row["table_name"]), oracle_downcase(row["db_link"]))
          end
        end
      end
    end
  end
end
