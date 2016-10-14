require 'digest/sha1'

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module SchemaStatements
        # SCHEMA STATEMENTS ========================================
        #
        # see: abstract/schema_statements.rb

        # Additional options for +create_table+ method in migration files.
        #
        # You can specify individual starting value in table creation migration file, e.g.:
        #
        #   create_table :users, :sequence_start_value => 100 do |t|
        #     # ...
        #   end
        #
        # You can also specify other sequence definition additional parameters, e.g.:
        #
        #   create_table :users, :sequence_start_value => “100 NOCACHE INCREMENT BY 10” do |t|
        #     # ...
        #   end
        #
        # Create primary key trigger (so that you can skip primary key value in INSERT statement).
        # By default trigger name will be "table_name_pkt", you can override the name with
        # :trigger_name option (but it is not recommended to override it as then this trigger will
        # not be detected by ActiveRecord model and it will still do prefetching of sequence value).
        # Example:
        #
        #   create_table :users, :primary_key_trigger => true do |t|
        #     # ...
        #   end
        #
        # It is possible to add table and column comments in table creation migration files:
        #
        #   create_table :employees, :comment => “Employees and contractors” do |t|
        #     t.string      :first_name, :comment => “Given name”
        #     t.string      :last_name, :comment => “Surname”
        #   end

        def create_table(table_name, comment: nil, **options)
          create_sequence = options[:id] != false
          td = create_table_definition table_name, options[:temporary], options[:options], options[:as], options[:tablespace], options[:organization], comment: comment

          if options[:id] != false && !options[:as]
            pk = options.fetch(:primary_key) do
              Base.get_primary_key table_name.to_s.singularize
            end

            if pk.is_a?(Array)
              td.primary_keys pk
            else
              td.primary_key pk, options.fetch(:id, :primary_key), options
            end
          end

          # store that primary key was defined in create_table block
          unless create_sequence
            class << td
              attr_accessor :create_sequence
              def primary_key(*args)
                self.create_sequence = true
                super(*args)
              end
            end
          end

          yield td if block_given?
          create_sequence = create_sequence || td.create_sequence

          if options[:force] && data_source_exists?(table_name)
            drop_table(table_name, options)
          end

          execute schema_creation.accept td

          create_sequence_and_trigger(table_name, options) if create_sequence

          if supports_comments? && !supports_comments_in_create?
            change_table_comment(table_name, comment) if comment
            td.columns.each do |column|
              change_column_comment(table_name, column.name, column.comment) if column.comment
            end
          end
          td.indexes.each { |c,o| add_index table_name, c, o }

        end

        def create_table_definition(*args)
          ActiveRecord::ConnectionAdapters::OracleEnhanced::TableDefinition.new(*args)
        end

        def rename_table(table_name, new_name) #:nodoc:
          if new_name.to_s.length > table_name_length
            raise ArgumentError, "New table name '#{new_name}' is too long; the limit is #{table_name_length} characters"
          end
          execute "RENAME #{quote_table_name(table_name)} TO #{quote_table_name(new_name)}"
          execute "RENAME #{quote_table_name("#{table_name}_seq")} TO #{default_sequence_name(new_name)}" rescue nil

          rename_table_indexes(table_name, new_name)
        end

        def drop_table(table_name, options = {}) #:nodoc:
          execute "DROP TABLE #{quote_table_name(table_name)}#{' CASCADE CONSTRAINTS' if options[:force] == :cascade}"
          seq_name = options[:sequence_name] || default_sequence_name(table_name)
          execute "DROP SEQUENCE #{quote_table_name(seq_name)}" rescue nil
        rescue ActiveRecord::StatementInvalid => e
          raise e unless options[:if_exists]
        ensure
          clear_table_columns_cache(table_name)
          self.all_schema_indexes = nil
        end

        def dump_schema_information #:nodoc:
          super
        end

        def initialize_schema_migrations_table
          super
        end

        def update_table_definition(table_name, base) #:nodoc:
          OracleEnhanced::Table.new(table_name, base)
        end

        def add_index(table_name, column_name, options = {}) #:nodoc:
          index_name, index_type, quoted_column_names, tablespace, index_options = add_index_options(table_name, column_name, options)
          execute "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{quoted_column_names})#{tablespace} #{index_options}"
          if index_type == 'UNIQUE'
            unless quoted_column_names =~ /\(.*\)/
              execute "ALTER TABLE #{quote_table_name(table_name)} ADD CONSTRAINT #{quote_column_name(index_name)} #{index_type} (#{quoted_column_names})"
            end
          end
        ensure
          self.all_schema_indexes = nil
        end

        def add_index_options(table_name, column_name, comment: nil, **options) #:nodoc:
          column_names = Array(column_name)
          index_name   = index_name(table_name, column: column_names)

          options.assert_valid_keys(:unique, :order, :name, :where, :length, :internal, :tablespace, :options, :using)

          index_type = options[:unique] ? "UNIQUE" : ""
          index_name = options[:name].to_s if options.key?(:name)
          tablespace = tablespace_for(:index, options[:tablespace])
          max_index_length = options.fetch(:internal, false) ? index_name_length : allowed_index_name_length
          #TODO: This option is used for NOLOGGING, needs better argumetn name
          index_options = options[:options]

          if index_name.to_s.length > max_index_length
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' is too long; the limit is #{max_index_length} characters"
          end
          if index_name_exists?(table_name, index_name, false)
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' already exists"
          end

          quoted_column_names = column_names.map { |e| quote_column_name_or_expression(e) }.join(", ")
           [index_name, index_type, quoted_column_names, tablespace, index_options]
        end

        # Remove the given index from the table.
        # Gives warning if index does not exist
        def remove_index(table_name, options = {}) #:nodoc:
          index_name = index_name_for_remove(table_name, options)
          unless index_name_exists?(table_name, index_name, true)
            # sometimes options can be String or Array with column names
            options = {} unless options.is_a?(Hash)
            if options.has_key? :name
              options_without_column = options.dup
              options_without_column.delete :column
              index_name_without_column = index_name(table_name, options_without_column)
              return index_name_without_column if index_name_exists?(table_name, index_name_without_column, false)
            end
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' does not exist"
          end
          #TODO: It should execute only when index_type == "UNIQUE"
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(index_name)}" rescue nil
          execute "DROP INDEX #{quote_column_name(index_name)}"
        ensure
          self.all_schema_indexes = nil
        end

        # returned shortened index name if default is too large
        def index_name(table_name, options) #:nodoc:
          default_name = super(table_name, options).to_s
          # sometimes options can be String or Array with column names
          options = {} unless options.is_a?(Hash)
          identifier_max_length = options[:identifier_max_length] || index_name_length
          return default_name if default_name.length <= identifier_max_length

          # remove 'index', 'on' and 'and' keywords
          shortened_name = "i_#{table_name}_#{Array(options[:column]) * '_'}"

          # leave just first three letters from each word
          if shortened_name.length > identifier_max_length
            shortened_name = shortened_name.split('_').map{|w| w[0,3]}.join('_')
          end
          # generate unique name using hash function
          if shortened_name.length > identifier_max_length
            shortened_name = 'i'+Digest::SHA1.hexdigest(default_name)[0,identifier_max_length-1]
          end
          @logger.warn "#{adapter_name} shortened default index name #{default_name} to #{shortened_name}" if @logger
          shortened_name
        end

        # Verify the existence of an index with a given name.
        #
        # The default argument is returned if the underlying implementation does not define the indexes method,
        # as there's no way to determine the correct answer in that case.
        #
        # Will always query database and not index cache.
        def index_name_exists?(table_name, index_name, default)
          (owner, table_name, db_link) = @connection.describe(table_name)
          result = select_value(<<-SQL)
            SELECT 1 FROM all_indexes#{db_link} i
            WHERE i.owner = '#{owner}'
               AND i.table_owner = '#{owner}'
               AND i.table_name = '#{table_name}'
               AND i.index_name = '#{index_name.to_s.upcase}'
          SQL
          result == 1
        end

        def rename_index(table_name, old_name, new_name) #:nodoc:
          unless index_name_exists?(table_name, old_name, true)
            raise ArgumentError, "Index name '#{old_name}' on table '#{table_name}' does not exist"
          end
          if new_name.length > allowed_index_name_length
            raise ArgumentError, "Index name '#{new_name}' on table '#{table_name}' is too long; the limit is #{allowed_index_name_length} characters"
          end
          execute "ALTER INDEX #{quote_column_name(old_name)} rename to #{quote_column_name(new_name)}"
        ensure
          self.all_schema_indexes = nil
        end

        def add_column(table_name, column_name, type, options = {}) #:nodoc:
          if type.to_sym == :virtual
            type = options[:type]
          end
          type = aliased_types(type.to_s, type)
          add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD #{quote_column_name(column_name)} "
          add_column_sql << type_to_sql(type, options[:limit], options[:precision], options[:scale]) if type

          add_column_options!(add_column_sql, options.merge(:type=>type, :column_name=>column_name, :table_name=>table_name))

          add_column_sql << tablespace_for((type_to_sql(type).downcase.to_sym), nil, table_name, column_name) if type

          execute(add_column_sql)

          create_sequence_and_trigger(table_name, options) if type && type.to_sym == :primary_key
          change_column_comment(table_name, column_name, options[:comment]) if options.key?(:comment)
        ensure
          clear_table_columns_cache(table_name)
        end

        def aliased_types(name, fallback)
          fallback
        end

        def change_column_default(table_name, column_name, default_or_changes) #:nodoc:
          default = extract_new_default_value(default_or_changes)
          execute "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} DEFAULT #{quote(default)}"
        ensure
          clear_table_columns_cache(table_name)
        end

        def change_column_null(table_name, column_name, null, default = nil) #:nodoc:
          column = column_for(table_name, column_name)

          unless null || default.nil?
            execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
          end

          change_column table_name, column_name, column.sql_type, :null => null
        end

        def change_column(table_name, column_name, type, options = {}) #:nodoc:
          column = column_for(table_name, column_name)

          # remove :null option if its value is the same as current column definition
          # otherwise Oracle will raise error
          if options.has_key?(:null) && options[:null] == column.null
            options[:null] = nil
          end
          if type.to_sym == :virtual
            type = options[:type]
          end
          change_column_sql = "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} "
          change_column_sql << "#{type_to_sql(type, options[:limit], options[:precision], options[:scale])}" if type

          add_column_options!(change_column_sql, options.merge(:type=>type, :column_name=>column_name, :table_name=>table_name))

          change_column_sql << tablespace_for((type_to_sql(type).downcase.to_sym), nil, options[:table_name], options[:column_name]) if type

          execute(change_column_sql)
        ensure
          clear_table_columns_cache(table_name)
        end

        def rename_column(table_name, column_name, new_column_name) #:nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}"
          self.all_schema_indexes = nil
          rename_column_indexes(table_name, column_name, new_column_name)
        ensure
          clear_table_columns_cache(table_name)
        end

        def remove_column(table_name, column_name, type = nil, options = {}) #:nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)} CASCADE CONSTRAINTS"
        ensure
          clear_table_columns_cache(table_name)
          self.all_schema_indexes = nil
        end

        def change_table_comment(table_name, comment)
          clear_cache!
          execute "COMMENT ON TABLE #{quote_table_name(table_name)} IS #{quote(comment)}"
        end

        def change_column_comment(table_name, column_name, comment) #:nodoc:
          clear_cache!
          execute "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} IS '#{comment}'"
        end

        def table_comment(table_name) #:nodoc:
          (owner, table_name, db_link) = @connection.describe(table_name)
          select_value <<-SQL
            SELECT comments FROM all_tab_comments#{db_link}
            WHERE owner = '#{owner}'
              AND table_name = '#{table_name}'
          SQL
        end

        def column_comment(table_name, column_name) #:nodoc:
          # TODO: it  does not exist in Abstract adapter
          (owner, table_name, db_link) = @connection.describe(table_name)
          select_value <<-SQL
            SELECT comments FROM all_col_comments#{db_link}
            WHERE owner = '#{owner}'
              AND table_name = '#{table_name}'
              AND column_name = '#{column_name.upcase}'
          SQL
        end

        # Maps logical Rails types to Oracle-specific data types.
        def type_to_sql(type, limit = nil, precision = nil, scale = nil) #:nodoc:
          # Ignore options for :text and :binary columns
          return super(type, nil, nil, nil) if ['text', 'binary'].include?(type.to_s)

          super
        end

        def tablespace(table_name)
          select_value <<-SQL
            SELECT tablespace_name
            FROM all_tables
            WHERE table_name='#{table_name.to_s.upcase}'
            AND owner = SYS_CONTEXT('userenv', 'session_user')
          SQL
        end

        def add_foreign_key(from_table, to_table, options = {})
          if options[:dependent]
            ActiveSupport::Deprecation.warn "`:dependent` option will be deprecated. Please use `:on_delete` option"
          end
          case options[:dependent]  
          when :delete then options[:on_delete] = :cascade
          when :nullify then options[:on_delete] = :nullify
          else
          end

          super
        end

        def remove_foreign_key(from_table, options_or_to_table = {})
          super
        end

        # get table foreign keys for schema dump
        def foreign_keys(table_name) #:nodoc:
          (owner, desc_table_name, db_link) = @connection.describe(table_name)

          fk_info = select_all(<<-SQL, 'Foreign Keys')
            SELECT r.table_name to_table
                  ,rc.column_name references_column
                  ,cc.column_name
                  ,c.constraint_name name
                  ,c.delete_rule
              FROM all_constraints#{db_link} c, all_cons_columns#{db_link} cc,
                   all_constraints#{db_link} r, all_cons_columns#{db_link} rc
             WHERE c.owner = '#{owner}'
               AND c.table_name = '#{desc_table_name}'
               AND c.constraint_type = 'R'
               AND cc.owner = c.owner
               AND cc.constraint_name = c.constraint_name
               AND r.constraint_name = c.r_constraint_name
               AND r.owner = c.owner
               AND rc.owner = r.owner
               AND rc.constraint_name = r.constraint_name
               AND rc.position = cc.position
            ORDER BY name, to_table, column_name, references_column
          SQL

          fk_info.map do |row|
            options = {
              column: oracle_downcase(row['column_name']),
              name: oracle_downcase(row['name']),
              primary_key: oracle_downcase(row['references_column'])
            }
            options[:on_delete] = extract_foreign_key_action(row['delete_rule'])
            OracleEnhanced::ForeignKeyDefinition.new(oracle_downcase(table_name), oracle_downcase(row['to_table']), options)
          end
        end

        def extract_foreign_key_action(specifier) # :nodoc:
          case specifier
          when 'CASCADE'; :cascade
          when 'SET NULL'; :nullify
          end
        end

        # REFERENTIAL INTEGRITY ====================================

        def disable_referential_integrity(&block) #:nodoc:
          sql_constraints = <<-SQL
          SELECT constraint_name, owner, table_name
            FROM all_constraints
            WHERE constraint_type = 'R'
            AND status = 'ENABLED'
            AND owner = SYS_CONTEXT('userenv', 'session_user')
          SQL
          old_constraints = select_all(sql_constraints)
          begin
            old_constraints.each do |constraint|
              execute "ALTER TABLE #{quote_table_name(constraint["table_name"])} DISABLE CONSTRAINT #{quote_table_name(constraint["constraint_name"])}"
            end
            yield
          ensure
            old_constraints.each do |constraint|
              execute "ALTER TABLE #{quote_table_name(constraint["table_name"])} ENABLE CONSTRAINT #{quote_table_name(constraint["constraint_name"])}"
            end
          end
        end

        private

        def create_alter_table(name)
          OracleEnhanced::AlterTable.new create_table_definition(name, false, {})
        end 

        def tablespace_for(obj_type, tablespace_option, table_name=nil, column_name=nil)
          tablespace_sql = ''
          if tablespace = (tablespace_option || default_tablespace_for(obj_type))
            tablespace_sql << if [:blob, :clob].include?(obj_type.to_sym)
             " LOB (#{quote_column_name(column_name)}) STORE AS #{column_name.to_s[0..10]}_#{table_name.to_s[0..14]}_ls (TABLESPACE #{tablespace})"
            else
             " TABLESPACE #{tablespace}"
            end
          end
          tablespace_sql
        end

        def default_tablespace_for(type)
          (default_tablespaces[type] || default_tablespaces[native_database_types[type][:name]]) rescue nil
        end


        def column_for(table_name, column_name)
          unless column = columns(table_name).find { |c| c.name == column_name.to_s }
            raise "No such column: #{table_name}.#{column_name}"
          end
          column
        end

        def create_sequence_and_trigger(table_name, options)
          seq_name = options[:sequence_name] || default_sequence_name(table_name)
          seq_start_value = options[:sequence_start_value] || default_sequence_start_value
          execute "CREATE SEQUENCE #{quote_table_name(seq_name)} START WITH #{seq_start_value}"

          create_primary_key_trigger(table_name, options) if options[:primary_key_trigger]
        end

        def create_primary_key_trigger(table_name, options)
          seq_name = options[:sequence_name] || default_sequence_name(table_name)
          trigger_name = options[:trigger_name] || default_trigger_name(table_name)
          primary_key = options[:primary_key] || Base.get_primary_key(table_name.to_s.singularize)
          execute compress_lines(<<-SQL)
            CREATE OR REPLACE TRIGGER #{quote_table_name(trigger_name)}
            BEFORE INSERT ON #{quote_table_name(table_name)} FOR EACH ROW
            BEGIN
              IF inserting THEN
                IF :new.#{quote_column_name(primary_key)} IS NULL THEN
                  SELECT #{quote_table_name(seq_name)}.NEXTVAL INTO :new.#{quote_column_name(primary_key)} FROM dual;
                END IF;
              END IF;
            END;
          SQL
        end

        def default_trigger_name(table_name)
          # truncate table name if necessary to fit in max length of identifier
          "#{table_name.to_s[0,table_name_length-4]}_pkt"
        end

      end
    end
  end
end
