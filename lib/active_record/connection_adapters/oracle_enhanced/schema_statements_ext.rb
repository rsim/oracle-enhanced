module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module SchemaStatementsExt
        # Create primary key trigger (so that you can skip primary key value in INSERT statement).
        # By default trigger name will be "table_name_pkt", you can override the name with
        # :trigger_name option (but it is not recommended to override it as then this trigger will
        # not be detected by ActiveRecord model and it will still do prefetching of sequence value).
        #
        #   add_primary_key_trigger :users
        #
        # You can also create primary key trigger using +create_table+ with :primary_key_trigger
        # option:
        #
        #   create_table :users, :primary_key_trigger => true do |t|
        #     # ...
        #   end
        #
        def add_primary_key_trigger(table_name, options={})
          # call the same private method that is used for create_table :primary_key_trigger => true
          create_primary_key_trigger(table_name, options)
        end

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
            OracleEnhanced::SynonymDefinition.new(oracle_downcase(row['synonym_name']),
              oracle_downcase(row['table_owner']), oracle_downcase(row['table_name']), oracle_downcase(row['db_link']))
          end
        end

      end
    end
  end
end
