# frozen_string_literal: true

require "openssl"

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module SchemaStatements
        # SCHEMA STATEMENTS ========================================
        #
        # see: abstract/schema_statements.rb

        def tables # :nodoc:
          select_values(<<~SQL.squish, "SCHEMA")
            SELECT
            DECODE(table_name, UPPER(table_name), LOWER(table_name), table_name)
            FROM all_tables
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
            AND secondary = 'N'
            minus
            SELECT DECODE(mview_name, UPPER(mview_name), LOWER(mview_name), mview_name)
            FROM all_mviews
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
        end

        def data_sources
          super | synonyms.map(&:name)
        end

        def table_exists?(table_name)
          table_name = table_name.to_s
          if table_name.include?("@")
            # db link is not table
            false
          else
            default_owner = current_schema
          end
          real_name = OracleEnhanced::Quoting.valid_table_name?(table_name) ?
            table_name.upcase : table_name
          if real_name.include?(".")
            table_owner, table_name = real_name.split(".")
          else
            table_owner, table_name = default_owner, real_name
          end

          select_values(<<~SQL.squish, "SCHEMA", [bind_string("owner", table_owner), bind_string("table_name", table_name)]).any?
            SELECT owner, table_name
            FROM all_tables
            WHERE owner = :owner
            AND table_name = :table_name
          SQL
        end

        def data_source_exists?(table_name)
          (_owner, _table_name) = _connection.describe(table_name)
          true
        rescue
          false
        end

        def views # :nodoc:
          select_values(<<~SQL.squish, "SCHEMA")
            SELECT
            LOWER(view_name) FROM all_views WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
        end

        def materialized_views # :nodoc:
          select_values(<<~SQL.squish, "SCHEMA")
            SELECT
            LOWER(mview_name) FROM all_mviews WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
        end

        # get synonyms for schema dump
        def synonyms
          result = select_all(<<~SQL.squish, "SCHEMA")
            SELECT synonym_name, table_owner, table_name
            FROM all_synonyms where owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL

          result.collect do |row|
             OracleEnhanced::SynonymDefinition.new(oracle_downcase(row["synonym_name"]),
             oracle_downcase(row["table_owner"]), oracle_downcase(row["table_name"]))
           end
        end

        def indexes(table_name) # :nodoc:
          (_owner, table_name) = _connection.describe(table_name)
          default_tablespace_name = default_tablespace

          result = select_all(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name)])
            SELECT LOWER(i.table_name) AS table_name, LOWER(i.index_name) AS index_name, i.uniqueness,
              i.index_type, i.ityp_owner, i.ityp_name, i.parameters,
              LOWER(i.tablespace_name) AS tablespace_name,
              LOWER(c.column_name) AS column_name, e.column_expression,
              atc.virtual_column
            FROM all_indexes i
              JOIN all_ind_columns c ON c.index_name = i.index_name AND c.index_owner = i.owner
              LEFT OUTER JOIN all_ind_expressions e ON e.index_name = i.index_name AND
                e.index_owner = i.owner AND e.column_position = c.column_position
              LEFT OUTER JOIN all_tab_cols atc ON i.table_name = atc.table_name AND
                c.column_name = atc.column_name AND i.owner = atc.owner AND atc.hidden_column = 'NO'
            WHERE i.owner = SYS_CONTEXT('userenv', 'current_schema')
               AND i.table_owner = SYS_CONTEXT('userenv', 'current_schema')
               AND i.table_name = :table_name
               AND NOT EXISTS (SELECT uc.index_name FROM all_constraints uc
                WHERE uc.index_name = i.index_name AND uc.owner = i.owner AND uc.constraint_type = 'P')
            ORDER BY i.index_name, c.column_position
          SQL

          current_index = nil
          all_schema_indexes = []

          result.each do |row|
            # have to keep track of indexes because above query returns dups
            # there is probably a better query we could figure out
            if current_index != row["index_name"]
              statement_parameters = nil
              if row["index_type"] == "DOMAIN" && row["ityp_owner"] == "CTXSYS" && row["ityp_name"] == "CONTEXT"
                procedure_name = default_datastore_procedure(row["index_name"])
                source = select_values(<<~SQL.squish, "SCHEMA", [bind_string("procedure_name", procedure_name.upcase)]).join
                  SELECT text
                  FROM all_source
                  WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
                    AND name = :procedure_name
                  ORDER BY line
                SQL
                if source =~ /-- add_context_index_parameters (.+)\n/
                  statement_parameters = $1
                end
              end
              all_schema_indexes << OracleEnhanced::IndexDefinition.new(
                row["table_name"],
                row["index_name"],
                row["uniqueness"] == "UNIQUE",
                [],
                {},
                row["index_type"] == "DOMAIN" ? "#{row['ityp_owner']}.#{row['ityp_name']}" : nil,
                row["parameters"],
                statement_parameters,
                row["tablespace_name"] == default_tablespace_name ? nil : row["tablespace_name"])
              current_index = row["index_name"]
            end

            # Functional index columns and virtual columns both get stored as column expressions,
            # but re-creating a virtual column index as an expression (instead of using the virtual column's name)
            # results in a ORA-54018 error.  Thus, we only want the column expression value returned
            # when the column is not virtual.
            if row["column_expression"] && row["virtual_column"] != "YES"
              all_schema_indexes.last.columns << row["column_expression"]
            else
              all_schema_indexes.last.columns << row["column_name"].downcase
            end
          end

          # Return the indexes just for the requested table, since AR is structured that way
          table_name = table_name.downcase
          all_schema_indexes.select { |i| i.table == table_name }
        end

        def columns(table_name)
          table_name = table_name.to_s
          if @columns_cache[table_name]
            @columns_cache[table_name]
          else
            @columns_cache[table_name] = super(table_name)
          end
        end
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

        def create_table(table_name, id: :primary_key, primary_key: nil, force: nil, **options)
          create_sequence = id != false
          td = create_table_definition(
            table_name, **options.extract!(:temporary, :options, :as, :comment, :tablespace, :organization)
          )

          if id && !td.as
            pk = primary_key || Base.get_primary_key(table_name.to_s.singularize)

            if pk.is_a?(Array)
              td.primary_keys pk
            else
              td.primary_key pk, id, **options
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

          if force && data_source_exists?(table_name)
            drop_table(table_name, force: force, if_exists: true)
          else
            schema_cache.clear_data_source_cache!(table_name.to_s)
          end

          execute schema_creation.accept td

          create_sequence_and_trigger(table_name, options) if create_sequence

          if supports_comments? && !supports_comments_in_create?
            if table_comment = td.comment.presence
              change_table_comment(table_name, table_comment)
            end
            td.columns.each do |column|
              change_column_comment(table_name, column.name, column.comment) if column.comment.present?
            end
          end
          td.indexes.each { |c, o| add_index table_name, c, **o }

          rebuild_primary_key_index_to_default_tablespace(table_name, options)
        end

        def rename_table(table_name, new_name) # :nodoc:
          if new_name.to_s.length > DatabaseLimits::IDENTIFIER_MAX_LENGTH
            raise ArgumentError, "New table name '#{new_name}' is too long; the limit is #{DatabaseLimits::IDENTIFIER_MAX_LENGTH} characters"
          end
          schema_cache.clear_data_source_cache!(table_name.to_s)
          schema_cache.clear_data_source_cache!(new_name.to_s)
          execute "RENAME #{quote_table_name(table_name)} TO #{quote_table_name(new_name)}"
          execute "RENAME #{quote_table_name("#{table_name}_seq")} TO #{default_sequence_name(new_name)}" rescue nil

          rename_table_indexes(table_name, new_name)
        end

        def drop_table(table_name, **options) # :nodoc:
          schema_cache.clear_data_source_cache!(table_name.to_s)
          execute "DROP TABLE #{quote_table_name(table_name)}#{' CASCADE CONSTRAINTS' if options[:force] == :cascade}"
          seq_name = options[:sequence_name] || default_sequence_name(table_name)
          execute "DROP SEQUENCE #{quote_table_name(seq_name)}" rescue nil
        rescue ActiveRecord::StatementInvalid => e
          raise e unless options[:if_exists]
        ensure
          clear_table_columns_cache(table_name)
        end

        def insert_versions_sql(versions) # :nodoc:
          sm_table = quote_table_name(ActiveRecord::SchemaMigration.table_name)

          if supports_multi_insert?
            versions.inject(+"INSERT ALL\n") { |sql, version|
              sql << "INTO #{sm_table} (version) VALUES (#{quote(version)})\n"
            } << "SELECT * FROM DUAL\n"
          else
            if versions.is_a?(Array)
              # called from ActiveRecord::Base.connection#dump_schema_information
              versions.map { |version|
                "INSERT INTO #{sm_table} (version) VALUES (#{quote(version)})"
              }.join("\n\n/\n\n")
            else
              # called from ActiveRecord::Base.connection#assume_migrated_upto_version
              "INSERT INTO #{sm_table} (version) VALUES (#{quote(versions)})"
            end
          end
        end

        def add_index(table_name, column_name, **options) # :nodoc:
          index_name, index_type, quoted_column_names, tablespace, index_options = add_index_options(table_name, column_name, **options)
          execute "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{quoted_column_names})#{tablespace} #{index_options}"
          if index_type == "UNIQUE"
            unless /\(.*\)/.match?(quoted_column_names)
              execute "ALTER TABLE #{quote_table_name(table_name)} ADD CONSTRAINT #{quote_column_name(index_name)} #{index_type} (#{quoted_column_names}) USING INDEX #{quote_column_name(index_name)}"
            end
          end
        end

        def add_index_options(table_name, column_name, comment: nil, **options) # :nodoc:
          column_names = Array(column_name)
          index_name   = index_name(table_name, column: column_names)

          options.assert_valid_keys(:unique, :order, :name, :where, :length, :internal, :tablespace, :options, :using)

          index_type = options[:unique] ? "UNIQUE" : ""
          index_name = options[:name].to_s if options.key?(:name)
          tablespace = tablespace_for(:index, options[:tablespace])
          # TODO: This option is used for NOLOGGING, needs better argument name
          index_options = options[:options]

          validate_index_length!(table_name, index_name, options.fetch(:internal, false))

          if table_exists?(table_name) && index_name_exists?(table_name, index_name)
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' already exists"
          end

          quoted_column_names = column_names.map { |e| quote_column_name_or_expression(e) }.join(", ")
          [index_name, index_type, quoted_column_names, tablespace, index_options]
        end

        # Remove the given index from the table.
        # Gives warning if index does not exist
        def remove_index(table_name, column_name = nil, **options) # :nodoc:
          return if options[:if_exists] && !index_exists?(table_name, column_name, **options)

          index_name = index_name_for_remove(table_name, column_name, options)
          # TODO: It should execute only when index_type == "UNIQUE"
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(index_name)}" rescue nil
          execute "DROP INDEX #{quote_column_name(index_name)}"
        end

        # returned shortened index name if default is too large
        def index_name(table_name, options) # :nodoc:
          default_name = super(table_name, options).to_s
          # sometimes options can be String or Array with column names
          options = {} unless options.is_a?(Hash)
          identifier_max_length = options[:identifier_max_length] || index_name_length
          return default_name if default_name.length <= identifier_max_length

          # remove 'index', 'on' and 'and' keywords
          shortened_name = "i_#{table_name}_#{Array(options[:column]) * '_'}"

          # leave just first three letters from each word
          if shortened_name.length > identifier_max_length
            shortened_name = shortened_name.split("_").map { |w| w[0, 3] }.join("_")
          end
          # generate unique name using hash function
          if shortened_name.length > identifier_max_length
            shortened_name = "i" + OpenSSL::Digest::SHA1.hexdigest(default_name)[0, identifier_max_length - 1]
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
        def index_name_exists?(table_name, index_name)
          (_owner, table_name) = _connection.describe(table_name)
          result = select_value(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name), bind_string("index_name", index_name.to_s.upcase)])
            SELECT 1 FROM all_indexes i
            WHERE i.owner = SYS_CONTEXT('userenv', 'current_schema')
               AND i.table_owner = SYS_CONTEXT('userenv', 'current_schema')
               AND i.table_name = :table_name
               AND i.index_name = :index_name
          SQL
          result == 1
        end

        def rename_index(table_name, old_name, new_name) # :nodoc:
          validate_index_length!(table_name, new_name)
          execute "ALTER INDEX #{quote_column_name(old_name)} rename to #{quote_column_name(new_name)}"
        end

        # Add synonym to existing table or view or sequence. Can be used to create local synonym to
        # remote table in other schema or in other database
        # Examples:
        #
        #   add_synonym :posts, "blog.posts"
        #   add_synonym :posts_seq, "blog.posts_seq"
        #   add_synonym :employees, "hr.employees", :force => true
        #
        def add_synonym(name, table_name, options = {})
          sql = +"CREATE"
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

        def add_reference(table_name, ref_name, **options)
          OracleEnhanced::ReferenceDefinition.new(ref_name, **options).add_to(update_table_definition(table_name, self))
        end

        def add_column(table_name, column_name, type, **options) # :nodoc:
          type = aliased_types(type.to_s, type)
          at = create_alter_table table_name
          at.add_column(column_name, type, **options)
          add_column_sql = schema_creation.accept at
          add_column_sql << tablespace_for((type_to_sql(type).downcase.to_sym), nil, table_name, column_name)
          execute add_column_sql
          create_sequence_and_trigger(table_name, options) if type && type.to_sym == :primary_key
          change_column_comment(table_name, column_name, options[:comment]) if options.key?(:comment)
        ensure
          clear_table_columns_cache(table_name)
        end

        def aliased_types(name, fallback)
          fallback
        end

        def change_column_default(table_name, column_name, default_or_changes) # :nodoc:
          default = extract_new_default_value(default_or_changes)
          execute "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} DEFAULT #{quote(default)}"
        ensure
          clear_table_columns_cache(table_name)
        end

        def change_column_null(table_name, column_name, null, default = nil) # :nodoc:
          column = column_for(table_name, column_name)

          unless null || default.nil?
            execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
          end

          change_column table_name, column_name, column.sql_type, null: null
        end

        def change_column(table_name, column_name, type, **options) # :nodoc:
          column = column_for(table_name, column_name)

          # remove :null option if its value is the same as current column definition
          # otherwise Oracle will raise error
          if options.has_key?(:null) && options[:null] == column.null
            options[:null] = nil
          end
          if type.to_sym == :virtual
            type = options[:type]
          end

          td = create_table_definition(table_name)
          cd = td.new_column_definition(column.name, type, **options)
          change_column_stmt = schema_creation.accept cd
          change_column_stmt << tablespace_for((type_to_sql(type).downcase.to_sym), nil, options[:table_name], options[:column_name]) if type
          change_column_sql = "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{change_column_stmt}"
          execute(change_column_sql)

          change_column_comment(table_name, column_name, options[:comment]) if options.key?(:comment)
        ensure
          clear_table_columns_cache(table_name)
        end

        def rename_column(table_name, column_name, new_column_name) # :nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}"
          rename_column_indexes(table_name, column_name, new_column_name)
        ensure
          clear_table_columns_cache(table_name)
        end

        def remove_column(table_name, column_name, type = nil, options = {}) # :nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)} CASCADE CONSTRAINTS"
        ensure
          clear_table_columns_cache(table_name)
        end

        def remove_columns(table_name, *column_names, type: nil, **options) # :nodoc:
          quoted_column_names = column_names.map { |column_name| quote_column_name(column_name) }.join(", ")

          execute "ALTER TABLE #{quote_table_name(table_name)} DROP (#{quoted_column_names}) CASCADE CONSTRAINTS"
        ensure
          clear_table_columns_cache(table_name)
        end

        def change_table_comment(table_name, comment_or_changes)
          clear_cache!
          comment = extract_new_comment_value(comment_or_changes)
          if comment.nil?
            execute "COMMENT ON TABLE #{quote_table_name(table_name)} IS ''"
          else
            execute "COMMENT ON TABLE #{quote_table_name(table_name)} IS #{quote(comment)}"
          end
        end

        def change_column_comment(table_name, column_name, comment_or_changes)
          clear_cache!
          comment = extract_new_comment_value(comment_or_changes)
          execute "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} IS '#{comment}'"
        end

        def table_comment(table_name) # :nodoc:
          # TODO
          (_owner, table_name) = _connection.describe(table_name)
          select_value(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name)])
            SELECT comments FROM all_tab_comments
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
              AND table_name = :table_name
          SQL
        end

        def table_options(table_name) # :nodoc:
          if comment = table_comment(table_name)
            { comment: comment }
          end
        end

        def column_comment(table_name, column_name) # :nodoc:
          # TODO: it  does not exist in Abstract adapter
          (_owner, table_name) = _connection.describe(table_name)
          select_value(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name), bind_string("column_name", column_name.upcase)])
            SELECT comments FROM all_col_comments
            WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
              AND table_name = :table_name
              AND column_name = :column_name
          SQL
        end

        # Maps logical Rails types to Oracle-specific data types.
        def type_to_sql(type, limit: nil, precision: nil, scale: nil, **) # :nodoc:
          # Ignore options for :text, :ntext and :binary columns
          return super(type) if ["text", "ntext", "binary"].include?(type.to_s)

          super
        end

        def tablespace(table_name)
          select_value(<<~SQL.squish, "SCHEMA")
            SELECT tablespace_name
            FROM all_tables
            WHERE table_name='#{table_name.to_s.upcase}'
            AND owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
        end

        # get table foreign keys for schema dump
        def foreign_keys(table_name) # :nodoc:
          (_owner, desc_table_name) = _connection.describe(table_name)

          fk_info = select_all(<<~SQL.squish, "SCHEMA", [bind_string("desc_table_name", desc_table_name)])
            SELECT r.table_name to_table
                  ,rc.column_name references_column
                  ,cc.column_name
                  ,c.constraint_name name
                  ,c.delete_rule
              FROM all_constraints c, all_cons_columns cc,
                   all_constraints r, all_cons_columns rc
             WHERE c.owner = SYS_CONTEXT('userenv', 'current_schema')
               AND c.table_name = :desc_table_name
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
              column: oracle_downcase(row["column_name"]),
              name: oracle_downcase(row["name"]),
              primary_key: oracle_downcase(row["references_column"])
            }
            options[:on_delete] = extract_foreign_key_action(row["delete_rule"])
            ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(oracle_downcase(table_name), oracle_downcase(row["to_table"]), options)
          end
        end

        def extract_foreign_key_action(specifier) # :nodoc:
          case specifier
          when "CASCADE"; :cascade
          when "SET NULL"; :nullify
          end
        end

        # REFERENTIAL INTEGRITY ====================================

        def disable_referential_integrity(&block) # :nodoc:
          old_constraints = select_all(<<~SQL.squish, "SCHEMA")
            SELECT constraint_name, owner, table_name
              FROM all_constraints
              WHERE constraint_type = 'R'
              AND status = 'ENABLED'
              AND owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
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

        def create_alter_table(name)
          OracleEnhanced::AlterTable.new create_table_definition(name)
        end

        def update_table_definition(table_name, base)
          OracleEnhanced::Table.new(table_name, base)
        end

        def create_schema_dumper(options)
          OracleEnhanced::SchemaDumper.create(self, options)
        end

        private
          def schema_creation
            OracleEnhanced::SchemaCreation.new self
          end

          def create_table_definition(name, **options)
            OracleEnhanced::TableDefinition.new(self, name, **options)
          end

          def new_column_from_field(table_name, field)
            limit, scale = field["limit"], field["scale"]
            if limit || scale
              field["sql_type"] += "(#{(limit || 38).to_i}" + ((scale = scale.to_i) > 0 ? ",#{scale})" : ")")
            end

            if field["sql_type_owner"]
              field["sql_type"] = field["sql_type_owner"] + "." + field["sql_type"]
            end

            is_virtual = field["virtual_column"] == "YES"

            # clean up odd default spacing from Oracle
            if field["data_default"] && !is_virtual
              field["data_default"].sub!(/^(.*?)\s*$/, '\1')

              # If a default contains a newline these cleanup regexes need to
              # match newlines.
              field["data_default"].sub!(/^'(.*)'$/m, '\1')
              field["data_default"] = nil if /^(null|empty_[bc]lob\(\))$/i.match?(field["data_default"])
              # TODO: Needs better fix to fallback "N" to false
              field["data_default"] = false if field["data_default"] == "N" && OracleEnhancedAdapter.emulate_booleans_from_strings
            end

            type_metadata = fetch_type_metadata(field["sql_type"], is_virtual)
            default_value = extract_value_from_default(field["data_default"])
            default_value = nil if is_virtual
            OracleEnhanced::Column.new(oracle_downcase(field["name"]),
                             default_value,
                             type_metadata,
                             field["nullable"] == "Y",
                             comment: field["column_comment"]
            )
          end

          def fetch_type_metadata(sql_type, virtual = nil)
            OracleEnhanced::TypeMetadata.new(super(sql_type), virtual: virtual)
          end

          def tablespace_for(obj_type, tablespace_option, table_name = nil, column_name = nil)
            tablespace_sql = +""
            if tablespace = (tablespace_option || default_tablespace_for(obj_type))
              if [:blob, :clob, :nclob].include?(obj_type.to_sym)
                tablespace_sql << " LOB (#{quote_column_name(column_name)}) STORE AS #{column_name.to_s[0..10]}_#{table_name.to_s[0..14]}_ls (TABLESPACE #{tablespace})"
              else
                tablespace_sql << " TABLESPACE #{tablespace}"
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
            # TODO: Needs rename since no triggers created
            # This method will be removed since sequence will not be created separately
            seq_name = options[:sequence_name] || default_sequence_name(table_name)
            seq_start_value = options[:sequence_start_value] || default_sequence_start_value
            execute "CREATE SEQUENCE #{quote_table_name(seq_name)} START WITH #{seq_start_value}"
          end

          def rebuild_primary_key_index_to_default_tablespace(table_name, options)
            tablespace = default_tablespace_for(:index)

            return unless tablespace

            index_name = select_value(<<~SQL.squish, "Index name for primary key",  [bind_string("table_name", table_name.upcase)])
              SELECT index_name FROM all_constraints
                  WHERE table_name = :table_name
                  AND constraint_type = 'P'
                  AND owner = SYS_CONTEXT('userenv', 'current_schema')
            SQL

            return unless index_name

            execute("ALTER INDEX #{quote_column_name(index_name)} REBUILD TABLESPACE #{tablespace}")
          end
      end
    end
  end
end
