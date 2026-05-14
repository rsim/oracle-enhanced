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
          real_name = OracleEnhanced::Quoting.valid_table_name?(table_name, max_identifier_length: max_identifier_length) ?
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
          return true if schema_cache.cached?(table_name.to_s)

          (_owner, _table_name) = resolve_data_source_name(table_name)
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
          (_owner, table_name) = resolve_data_source_name(table_name)
          default_tablespace_name = default_tablespace

          # `all_indexes.visibility` was introduced in Oracle 11g R1. Pre-11g
          # connections do not have the column, so substitute a literal
          # 'VISIBLE' so the rest of the reader works unchanged.
          visibility_column = supports_disabling_indexes? ? "i.visibility" : "'VISIBLE' AS visibility"
          result = select_all(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name)])
            SELECT LOWER(i.table_name) AS table_name, LOWER(i.index_name) AS index_name, i.uniqueness,
              i.index_type, i.ityp_owner, i.ityp_name, i.parameters,
              LOWER(i.tablespace_name) AS tablespace_name, #{visibility_column},
              LOWER(c.column_name) AS column_name, c.descend, e.column_expression,
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
                type: row["index_type"] == "DOMAIN" ? "#{row['ityp_owner']}.#{row['ityp_name']}" : nil,
                parameters: row["parameters"],
                statement_parameters: statement_parameters,
                enabled: row["visibility"] != "INVISIBLE",
                tablespace: row["tablespace_name"] == default_tablespace_name ? nil : row["tablespace_name"])
              current_index = row["index_name"]
            end

            expression = row["column_expression"]
            user_defined_virtual_column = row["virtual_column"] == "YES"
            column = if user_defined_virtual_column || expression.nil?
              # Plain column or user-defined virtual column. Re-creating a
              # virtual-column index as an expression (instead of using the
              # virtual column's name) results in ORA-54018, so use the
              # column name in both cases.
              row["column_name"].downcase
            elsif row["descend"] == "DESC" && expression =~ /\A"([^"]+)"\z/ # quoted-bare-identifier ("LAST_NAME"); function expressions like LOWER("NAME") fail to match
              # Oracle implements `(col DESC)` via a system-generated virtual
              # column whose column_expression is the quoted user column
              # name. Peel that off so the orders hash keys off the bare name.
              # Example: column_name = SYS_NC00003$, column_expression = "LAST_NAME"
              # -> column = "last_name", orders["last_name"] = :desc.
              $1.downcase
            else
              # Function-based expression (e.g. `LOWER("NAME")`).
              expression
            end
            all_schema_indexes.last.columns << column
            # Track DESC only for plain column names. A function-based DESC index
            # (column = expression) would dump as `order: { LOWER("NAME"): :desc }`,
            # which AR core's hash formatter emits in symbol-shorthand form and
            # produces invalid Ruby. Plain columns / DESC-marker virtuals are safe
            # because `column` is downcased and identifier-like.
            if row["descend"] == "DESC" && column != expression
              all_schema_indexes.last.orders[column] = :desc
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
          # Mirror upstream guard: `super` is called with `force: nil` below, so the same check there is bypassed.
          if force && options.key?(:if_not_exists)
            raise ArgumentError, "Options `:force` and `:if_not_exists` cannot be used simultaneously."
          end

          identity = options[:identity]
          validate_identity_options!(identity, id, primary_key)
          validate_primary_key_trigger_options!(options[:primary_key_trigger], identity, id, primary_key)

          if force && data_source_exists?(table_name)
            drop_table(table_name, force: force, if_exists: true)
          elsif options[:if_not_exists] && data_source_exists?(table_name)
            # Oracle 21c and earlier do not support `CREATE TABLE IF NOT EXISTS` DDL;
            # pre-check existence in Ruby so the emitted SQL stays identical across
            # all supported Oracle releases.
            return
          end

          captured_td = nil
          super(table_name, id: id, primary_key: primary_key, force: nil, **options) do |td|
            captured_td = td
            yield td if block_given?
          end

          add_inline_unique_constraints(table_name, captured_td)

          create_pk_sequence(table_name, options) if should_create_sequence?(captured_td, id, identity)
          create_pk_trigger(table_name, primary_key, options) if options[:primary_key_trigger]
          rebuild_primary_key_index_to_default_tablespace(table_name, options)
        end

        def rename_table(table_name, new_name, **options) # :nodoc:
          if new_name.to_s.bytesize > max_identifier_length
            raise ArgumentError, "New table name '#{new_name}' is too long; the limit is #{max_identifier_length} bytes"
          end
          schema_cache.clear_data_source_cache!(table_name.to_s)
          schema_cache.clear_data_source_cache!(new_name.to_s)
          execute "RENAME #{quote_table_name(table_name)} TO #{quote_table_name(new_name)}"
          execute "RENAME #{default_sequence_name(table_name, nil)} TO #{default_sequence_name(new_name, nil)}" rescue nil
          rename_pk_trigger(table_name, new_name)
          clear_table_caches(table_name)
          clear_table_caches(new_name)

          rename_table_indexes(table_name, new_name, **options)
        end

        def drop_table(*table_names, **options) # :nodoc:
          # :sequence_name names a single sequence, so it cannot unambiguously
          # apply across multiple tables; honor it only for single-table drops.
          custom_sequence_name = table_names.size == 1 ? options[:sequence_name] : nil
          if_exists = options[:if_exists]
          cascade = options[:force] == :cascade

          table_names.each do |table_name|
            schema_cache.clear_data_source_cache!(table_name.to_s)
            seq_name = custom_sequence_name || default_sequence_name(table_name, nil)

            drop_if_exists("TABLE", table_name, cascade_constraints: cascade, if_exists: if_exists)
            drop_if_exists("SEQUENCE", seq_name, if_exists: true)
          ensure
            clear_table_caches(table_name)
          end
        end

        def drop_if_exists(object_type, name, if_exists: true, cascade_constraints: false) # :nodoc:
          cascade_clause = " CASCADE CONSTRAINTS" if cascade_constraints
          if supports_drop_if_exists?
            if_exists_clause = " IF EXISTS" if if_exists
            execute "DROP #{object_type}#{if_exists_clause} #{quote_table_name(name)}#{cascade_clause}"
          else
            execute "DROP #{object_type} #{quote_table_name(name)}#{cascade_clause}"
          end
        rescue ActiveRecord::StatementInvalid => e
          raise unless if_exists && missing_object_ora_code?(e.message, object_type)
        end

        def add_index(table_name, column_name, **options) # :nodoc:
          create_index = build_create_index_definition(table_name, column_name, **options)
          return unless create_index

          execute schema_creation.accept(create_index)

          index = create_index.index
          if needs_unique_constraint?(index.unique, index.columns) && OracleEnhancedAdapter.add_index_unique_creates_constraint
            warn_implicit_unique_constraint_deprecation
            execute add_unique_constraint_sql(index.table, index.columns, index.name)
          end
        end

        def build_create_index_definition(table_name, column_name, **options) # :nodoc:
          index, algorithm, if_not_exists = add_index_options(table_name, column_name, **options)

          if table_exists?(table_name) && index_name_exists?(table_name, index.name)
            return if if_not_exists
            raise ArgumentError, "Index name '#{index.name}' on table '#{table_name}' already exists"
          end

          CreateIndexDefinition.new(index, algorithm, if_not_exists)
        end

        def add_index_options(table_name, column_name, name: nil, if_not_exists: false, internal: false, enabled: true, **options) # :nodoc:
          options.assert_valid_keys(:unique, :order, :where, :length, :tablespace, :options, :using, :comment)

          if enabled == false && !supports_disabling_indexes?
            raise ArgumentError, "`enabled: false` requires Oracle Database 11g or later (it is implemented via `INVISIBLE` indexes)"
          end

          column_names = index_column_names(column_name)
          index_name = name&.to_s || index_name(table_name, column: column_names)

          validate_index_length!(table_name, index_name, internal)

          index = OracleEnhanced::IndexDefinition.new(
            table_name,
            index_name,
            options[:unique] || false,
            column_names,
            options[:order] || {},
            statement_parameters: options[:options],
            enabled: enabled,
            tablespace: options[:tablespace] || default_tablespace_for(:index)
          )

          [index, nil, if_not_exists]
        end

        # Remove the given index from the table.
        # Gives warning if index does not exist
        def remove_index(table_name, column_name = nil, **options) # :nodoc:
          return if options[:if_exists] && !index_exists?(table_name, column_name, **options)

          index_name = index_name_for_remove(table_name, column_name, options).to_s
          ucs = unique_constraints(table_name)

          divergent = ucs.detect { |uc| uc.using_index == index_name }
          if divergent
            raise ArgumentError, "Index '#{index_name}' on table '#{table_name}' is used by unique constraint '#{divergent.name}' (USING INDEX #{index_name}). Call remove_unique_constraint(:#{table_name}, name: \"#{divergent.name}\") first, then remove_index."
          end

          if ucs.any? { |uc| uc.name == index_name }
            execute "ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(index_name)}"
          end
          execute "DROP INDEX #{quote_column_name(index_name)}"
        end

        # returned shortened index name if default is too large
        def index_name(table_name, options) # :nodoc:
          default_name = super(table_name, options).to_s
          # sometimes options can be String or Array with column names
          options = {} unless options.is_a?(Hash)
          identifier_max_length = options[:identifier_max_length] || index_name_length
          return default_name if default_name.bytesize <= identifier_max_length

          # remove 'index', 'on' and 'and' keywords
          shortened_name = "i_#{table_name}_#{Array(options[:column]) * '_'}"

          # leave just first three letters from each word
          if shortened_name.bytesize > identifier_max_length
            shortened_name = shortened_name.split("_").map { |w| w[0, 3] }.join("_")
          end
          # generate unique name using hash function
          if shortened_name.bytesize > identifier_max_length
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
          (_owner, table_name) = resolve_data_source_name(table_name)
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

        # Make the index invisible to the optimizer so queries stop using it
        # while leaving it maintained on writes. Oracle 11g+ feature.
        # The first argument is named with a leading underscore because Oracle
        # index identifiers are schema-scoped, so the table is not part of the
        # `ALTER INDEX` statement; the parameter exists only to match the
        # MySQL adapter's contract.
        def disable_index(_table_name, index_name) # :nodoc:
          raise NotImplementedError unless supports_disabling_indexes?
          execute "ALTER INDEX #{quote_column_name(index_name)} INVISIBLE"
        end

        def enable_index(_table_name, index_name) # :nodoc:
          raise NotImplementedError unless supports_disabling_indexes?
          execute "ALTER INDEX #{quote_column_name(index_name)} VISIBLE"
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
          # Adding a `GENERATED ... AS IDENTITY` column with `ALTER TABLE` is
          # rejected by Oracle when the table already has rows or an existing
          # primary key, because identity columns are implicitly NOT NULL and a
          # table can only have one primary key:
          #   ORA-01758: table must be empty to add mandatory (NOT NULL) column
          #     https://docs.oracle.com/error-help/db/ora-01758/
          #   ORA-02260: table can have only one primary key
          #     https://docs.oracle.com/error-help/db/ora-02260/
          # See ALTER TABLE / identity_clause in the Oracle SQL Language Reference:
          #   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLE.html
          if options[:identity]
            raise ArgumentError,
              "`identity: true` is not supported on `add_column`. Recreate the table with `create_table ..., identity: true` instead."
          end
          if options[:primary_key_trigger] && type.to_s.to_sym != :primary_key
            raise ArgumentError,
              "`primary_key_trigger: true` on `add_column` requires the column type to be `:primary_key`; got type: #{type.inspect}."
          end
          type = aliased_types(type.to_s, type)
          at = create_alter_table table_name
          at.add_column(column_name, type, **options)
          add_column_sql = schema_creation.accept at
          add_column_sql << tablespace_for((type_to_sql(type).downcase.to_sym), nil, table_name, column_name)
          execute add_column_sql
          if type.to_sym == :primary_key
            create_pk_sequence(table_name, options)
            create_pk_trigger(table_name, column_name, options) if options[:primary_key_trigger]
          end
          apply_column_comments(table_name, column_name, comment: options[:comment]) if options.key?(:comment)
        ensure
          clear_table_caches(table_name)
        end

        def aliased_types(name, fallback)
          fallback
        end

        def change_column_default(table_name, column_name, default_or_changes) # :nodoc:
          default = extract_new_default_value(default_or_changes)
          execute "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{quote_column_name(column_name)} DEFAULT #{quote(default)}"
        ensure
          clear_table_caches(table_name)
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
          change_column_sql = "ALTER TABLE #{quote_table_name(table_name)} MODIFY #{change_column_stmt}"
          execute(change_column_sql)

          apply_column_comments(table_name, column_name, comment: options[:comment]) if options.key?(:comment)
        ensure
          clear_table_caches(table_name)
        end

        def rename_column(table_name, column_name, new_column_name) # :nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} to #{quote_column_name(new_column_name)}"
          rename_column_indexes(table_name, column_name, new_column_name)
        ensure
          clear_table_caches(table_name)
        end

        def remove_column(table_name, column_name, type = nil, **options) # :nodoc:
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)} CASCADE CONSTRAINTS"
        ensure
          clear_table_caches(table_name)
        end

        def remove_columns(table_name, *column_names, type: nil, **options) # :nodoc:
          quoted_column_names = column_names.map { |column_name| quote_column_name(column_name) }.join(", ")

          execute "ALTER TABLE #{quote_table_name(table_name)} DROP (#{quoted_column_names}) CASCADE CONSTRAINTS"
        ensure
          clear_table_caches(table_name)
        end

        # Commands the bulk dispatcher knows how to combine into Oracle's
        # ADD/MODIFY/DROP buckets. Anything else raises `NotImplementedError`
        # *before* any DDL fires, so `change_table(bulk: true)` never
        # half-applies a migration.
        SUPPORTED_BULK_COMMANDS = %i[
          add_column
          add_timestamps
          change_column
          change_column_default
          change_column_null
          remove_column
          remove_columns
          remove_timestamps
        ].freeze
        private_constant :SUPPORTED_BULK_COMMANDS

        def bulk_change_table(table_name, operations) # :nodoc:
          # Two ALTER buckets (ORA-12987 forbids mixing ADD/MODIFY with DROP).
          # Invariant: never let a DROP sit pending while we queue an ADD/MODIFY,
          # and vice versa — flushing the *other* bucket at every kind switch
          # preserves the user's operation order across the two ALTER statements.
          unsupported = operations.map(&:first).reject { |c| SUPPORTED_BULK_COMMANDS.include?(c) }
          if unsupported.any?
            raise NotImplementedError,
              "bulk_change_table only supports #{SUPPORTED_BULK_COMMANDS.inspect} " \
              "(got #{unsupported.first.inspect}); use change_table(bulk: false)"
          end

          # Collect comments from `:add_timestamps` ops *before* expansion so
          # the synthesised `:add_column` ops can drop `:comment` and stay on
          # the bulk fragment path. The comments fire after the bulk ALTER
          # via `apply_column_comments`, matching the non-bulk
          # `add_timestamps` flow (1 combined ADD + N COMMENT ON COLUMN).
          pending_timestamps_comments = collect_timestamps_comments(operations)
          operations = expand_bulk_timestamps(operations)

          add_buf = []
          modify_buf = []
          drop_buf = []
          add_pending = [] # column names queued in add_buf — see :change_column branch

          operations.each do |command, args|
            args = args.dup
            args.shift # remove table_name

            case command
            when :add_column
              column_name, type, options = args[0], args[1], (args[2] || {})
              if requires_full_command?(:add_column, type, options)
                flush_bulk_buffers(table_name, add_buf, modify_buf, drop_buf)
                add_pending.clear
                add_column(table_name, column_name, type, **options)
              else
                flush_bulk_drops(table_name, drop_buf)
                add_buf << add_column_for_alter(table_name, column_name, type, **options)
                add_pending << quote_column_name(column_name)
              end
            when :change_column
              column_name, type, options = args[0], args[1], (args[2] || {})
              if requires_full_command?(:change_column, type, options)
                flush_bulk_buffers(table_name, add_buf, modify_buf, drop_buf)
                add_pending.clear
                change_column(table_name, column_name, type, **options)
              else
                flush_bulk_drops(table_name, drop_buf)
                if needs_pre_modify_flush?(add_buf, modify_buf, add_pending, column_name)
                  flush_bulk_add_modify(table_name, add_buf, modify_buf)
                  add_pending.clear
                end
                modify_buf << change_column_for_alter(table_name, column_name, type, **options)
              end
            when :change_column_default
              column_name = args[0]
              flush_bulk_drops(table_name, drop_buf)
              if needs_pre_modify_flush?(add_buf, modify_buf, add_pending, column_name)
                flush_bulk_add_modify(table_name, add_buf, modify_buf)
                add_pending.clear
              end
              modify_buf << change_column_default_for_alter(table_name, *args)
            when :change_column_null
              column_name, null, default = args[0], args[1], args[2]
              if !null && !default.nil?
                # change_column_null with a default value runs an UPDATE before
                # the MODIFY to backfill NULLs, which can't combine into ALTER.
                flush_bulk_buffers(table_name, add_buf, modify_buf, drop_buf)
                add_pending.clear
                change_column_null(table_name, column_name, null, default)
              else
                flush_bulk_drops(table_name, drop_buf)
                if needs_pre_modify_flush?(add_buf, modify_buf, add_pending, column_name)
                  flush_bulk_add_modify(table_name, add_buf, modify_buf)
                  add_pending.clear
                end
                fragment = change_column_null_for_alter(table_name, *args)
                modify_buf << fragment if fragment
              end
            when :remove_column
              flush_bulk_add_modify(table_name, add_buf, modify_buf)
              add_pending.clear
              drop_buf << args[0] # column_name
            when :remove_columns
              flush_bulk_add_modify(table_name, add_buf, modify_buf)
              add_pending.clear
              drop_buf.concat(args.reject { |a| a.is_a?(Hash) })
            else
              raise "missing dispatch branch for #{command.inspect}; update both SUPPORTED_BULK_COMMANDS and the case statement"
            end
          end

          flush_bulk_buffers(table_name, add_buf, modify_buf, drop_buf)

          pending_timestamps_comments.each do |comment|
            apply_column_comments(table_name, :created_at, :updated_at, comment: comment)
          end
        ensure
          clear_table_caches(table_name)
        end

        def change_table_comment(table_name, comment_or_changes)
          clear_cache!
          execute change_table_comment_sql(table_name, comment_or_changes)
        end

        def change_column_comment(table_name, column_name, comment_or_changes)
          clear_cache!
          execute change_column_comment_sql(table_name, column_name, comment_or_changes)
        end

        def table_comment(table_name) # :nodoc:
          # TODO
          (_owner, table_name) = resolve_data_source_name(table_name)
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
          (_owner, table_name) = resolve_data_source_name(table_name)
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
          select_value(<<~SQL.squish, "SCHEMA", [bind_string("table_name", table_name.to_s.upcase)])
            SELECT tablespace_name
            FROM all_tables
            WHERE table_name = :table_name
            AND owner = SYS_CONTEXT('userenv', 'current_schema')
          SQL
        end

        def add_foreign_key(from_table, to_table, **options)
          assert_valid_deferrable(options[:deferrable])

          super
        end

        # get table foreign keys for schema dump
        def foreign_keys(table_name) # :nodoc:
          (_owner, desc_table_name) = resolve_data_source_name(table_name)

          fk_info = select_all(<<~SQL.squish, "SCHEMA", [bind_string("desc_table_name", desc_table_name)])
            SELECT r.table_name to_table
                  ,rc.column_name references_column
                  ,cc.column_name
                  ,c.constraint_name name
                  ,c.delete_rule
                  ,c.deferrable
                  ,c.deferred
                  ,c.validated
                  ,c.status
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
            options[:deferrable] = extract_foreign_key_deferrable(row["deferrable"], row["deferred"])
            options[:enforced] = false if row["status"] == "DISABLED"
            options[:validate] = false if row["validated"] == "NOT VALIDATED"
            ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(oracle_downcase(table_name), oracle_downcase(row["to_table"]), options)
          end
        end

        # `generated = 'USER NAME'` skips implicit NOT NULL checks (system-named, type 'C').
        def check_constraints(table_name) # :nodoc:
          (_owner, desc_table_name) = resolve_data_source_name(table_name)

          # `search_condition` is LONG; cannot appear in WHERE (ORA-00997).
          rows = select_all(<<~SQL.squish, "SCHEMA", [bind_string("desc_table_name", desc_table_name)])
            SELECT constraint_name AS name, search_condition, validated
              FROM all_constraints
             WHERE owner = SYS_CONTEXT('userenv', 'current_schema')
               AND table_name = :desc_table_name
               AND constraint_type = 'C'
               AND generated = 'USER NAME'
             ORDER BY constraint_name
          SQL

          rows.filter_map do |row|
            next if row["search_condition"].nil?
            options = { name: oracle_downcase(row["name"]) }
            options[:validate] = false if row["validated"] == "NOT VALIDATED"
            CheckConstraintDefinition.new(oracle_downcase(table_name), row["search_condition"], options)
          end
        end

        def validate_constraint(table_name, constraint_name) # :nodoc:
          at = create_alter_table(table_name)
          at.validate_constraint(constraint_name)

          execute schema_creation.accept(at)
        end

        def validate_check_constraint(table_name, **options) # :nodoc:
          chk_name_to_validate = check_constraint_for!(table_name, **options).name
          validate_constraint(table_name, chk_name_to_validate)
        end

        def validate_foreign_key(from_table, to_table = nil, **options) # :nodoc:
          fk_name_to_validate = foreign_key_for!(from_table, to_table: to_table, **options).name
          validate_constraint(from_table, fk_name_to_validate)
        end

        # Accepted options: +:enforced+ (the only mutable axis) plus the identifying
        # keys +:column+, +:name+, +:to_table+ passed through to +foreign_key_for!+.
        # ALTER ... MODIFY CONSTRAINT name DISABLE/ENABLE follows Oracle's defaults:
        # bare DISABLE leaves the constraint at DISABLE NOVALIDATE, and bare ENABLE
        # at ENABLE VALIDATE; introspection reflects those side effects on +:validate+.
        def change_foreign_key(from_table, to_table = nil, **options) # :nodoc:
          unless options.key?(:enforced)
            raise ArgumentError, "change_foreign_key requires at least one option (e.g. enforced:)"
          end
          enforced = options[:enforced]
          fk_name = foreign_key_for!(from_table, to_table: to_table, **options.except(:enforced)).name
          execute "ALTER TABLE #{quote_table_name(from_table)} MODIFY CONSTRAINT #{quote_column_name(fk_name)} #{enforced ? 'ENABLE' : 'DISABLE'}"
        end

        # Returns an array of unique constraints for the given table.
        # The unique constraints are represented as UniqueConstraintDefinition objects.
        def unique_constraints(table_name) # :nodoc:
          (_owner, desc_table_name) = resolve_data_source_name(table_name)

          rows = select_all(<<~SQL.squish, "SCHEMA", [bind_string("desc_table_name", desc_table_name)])
            SELECT c.constraint_name AS name,
                   c.index_name,
                   c.deferrable,
                   c.deferred,
                   cc.column_name,
                   cc.position
              FROM all_constraints c
              JOIN all_cons_columns cc
                ON cc.owner = c.owner
               AND cc.constraint_name = c.constraint_name
             WHERE c.owner = SYS_CONTEXT('userenv', 'current_schema')
               AND c.table_name = :desc_table_name
               AND c.constraint_type = 'U'
             ORDER BY c.constraint_name, cc.position
          SQL

          grouped = rows.group_by { |row| row["name"] }
          grouped.map do |name, group|
            columns = group.sort_by { |r| r["position"] }.map { |r| oracle_downcase(r["column_name"]) }
            sample = group.first
            constraint_name = oracle_downcase(name)
            index_name = oracle_downcase(sample["index_name"])

            options = { name: constraint_name }
            options[:deferrable] = extract_foreign_key_deferrable(sample["deferrable"], sample["deferred"])
            if index_name && index_name != constraint_name
              options[:using_index] = index_name
            end

            OracleEnhanced::UniqueConstraintDefinition.new(oracle_downcase(table_name), columns, options)
          end
        end

        # Adds a new unique constraint to the table.
        #
        #   add_unique_constraint :sections, :position, name: "uniq_position", deferrable: :deferred
        #
        # generates:
        #
        #   ALTER TABLE "sections" ADD CONSTRAINT uniq_position UNIQUE ("position") DEFERRABLE INITIALLY DEFERRED
        #
        # If you want the constraint to attach to an existing unique index, use +:using_index+.
        # Oracle, unlike PostgreSQL, allows the constraint name to differ from its backing index.
        #
        #   add_unique_constraint :sections, name: "uniq_position", using_index: "index_sections_on_position"
        def add_unique_constraint(table_name, column_name = nil, **options)
          # Oracle's UNIQUE constraint syntax requires the column list even with USING INDEX.
          if column_name.nil? && options[:using_index]
            index = indexes(table_name).detect { |idx| idx.name.to_s == options[:using_index].to_s }
            raise ArgumentError, "No index '#{options[:using_index]}' found on '#{table_name}'" unless index
            column_name = index.columns
          end

          options = unique_constraint_options(table_name, column_name, options)

          if unique_constraints(table_name).any? { |uc| uc.name == options[:name].to_s }
            raise ArgumentError, "Table '#{table_name}' already has a unique constraint named '#{options[:name]}'"
          end

          at = create_alter_table(table_name)
          at.add_unique_constraint(column_name, options)

          execute schema_creation.accept(at)
        end

        def unique_constraint_options(table_name, column_name, options) # :nodoc:
          assert_valid_deferrable(options[:deferrable])

          if column_name && Array(column_name).any? { |c| c.to_s.include?("(") }
            raise ArgumentError, "Unique constraints do not support expression columns. Use add_index with :unique => true for functional uniqueness."
          end

          options = options.dup
          options[:name] ||= unique_constraint_name(table_name, column: column_name, **options)
          options
        end

        # Removes the given unique constraint from the table.
        #
        #   remove_unique_constraint :sections, name: "uniq_position"
        #
        # The +column_name+ parameter will be ignored if present. It can be helpful
        # to provide this in a migration's +change+ method so it can be reverted.
        # In that case, +column_name+ will be used by #add_unique_constraint.
        def remove_unique_constraint(table_name, column_name = nil, **options)
          unique_name_to_delete = unique_constraint_for!(table_name, column: column_name, **options).name

          execute "ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(unique_name_to_delete)}"
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

        def add_timestamps(table_name, **options)
          options[:null] = false if options[:null].nil?
          options[:precision] = 6 if !options.key?(:precision) && supports_datetime_with_precision?
          column_options = options.except(:comment)
          change_table(table_name, bulk: true) do |t|
            t.column :created_at, :datetime, **column_options
            t.column :updated_at, :datetime, **column_options
          end
          apply_column_comments(table_name, :created_at, :updated_at, comment: options[:comment]) if options.key?(:comment)
        end

        def update_table_definition(table_name, base) # :nodoc:
          OracleEnhanced::Table.new(table_name, base)
        end

        def create_schema_dumper(options) # :nodoc:
          OracleEnhanced::SchemaDumper.create(self, options)
        end

        def schema_creation # :nodoc:
          OracleEnhanced::SchemaCreation.new self
        end

        def valid_table_definition_options # :nodoc:
          super + [:tablespace, :organization]
        end

        def valid_primary_key_options # :nodoc:
          super + [:identity, :sequence_name, :sequence_start_value, :primary_key_trigger, :trigger_name]
        end

        def default_trigger_name(table_name) # :nodoc:
          table_name.to_s.gsub(/(\A|\.)([[:word:]$#-]+)\z/) do
            prefix = Regexp.last_match(1)
            name = Regexp.last_match(2)
            max_bytes = max_identifier_length - 4
            if name.bytesize > max_bytes
              name = name.byteslice(0, max_bytes)
              name = name.byteslice(0, name.bytesize - 1) until name.bytesize.zero? || name.valid_encoding?
            end
            "#{prefix}#{name}_pkt"
          end
        end

        def quoted_columns_for_index(column_names, options) # :nodoc:
          quoted_columns = column_names.each_with_object({}) do |name, result|
            result[name.to_sym] = quote_column_name_or_expression(name).dup
          end
          add_options_for_index_columns(quoted_columns, **options).values.join(", ")
        end

        private
          # Oracle does not allow inline `COMMENT '...'` in `ALTER TABLE
          # ADD` / `MODIFY`, so column comments are issued as separate
          # `COMMENT ON COLUMN` statements after the column DDL is in
          # place. Centralising the post-ALTER call here keeps
          # `add_column`, `change_column` and `add_timestamps` in lockstep.
          # The helper does not short-circuit on `comment.nil?` because
          # passing `comment: nil` is the canonical way for callers to
          # clear an existing column comment (`change_column_comment_sql`
          # turns a nil comment into `COMMENT ON COLUMN ... IS ''`); the
          # `options.key?(:comment)` guard at each call site is what
          # decides whether the helper runs at all.
          def apply_column_comments(table_name, *column_names, comment:)
            column_names.each do |column_name|
              change_column_comment(table_name, column_name, comment)
            end
          end

          def add_column_for_alter(table_name, column_name, type, **options)
            if options[:identity]
              raise ArgumentError,
                "`identity: true` is not supported on `add_column`. Recreate the table with `create_table ..., identity: true` instead."
            end
            if options[:primary_key_trigger] && type.to_s.to_sym != :primary_key
              raise ArgumentError,
                "`primary_key_trigger: true` on `add_column` requires the column type to be `:primary_key`; got type: #{type.inspect}."
            end
            type = aliased_types(type.to_s, type)
            td = create_table_definition(table_name)
            cd = td.new_column_definition(column_name, type, **options)
            schema_creation.accept(cd)
          end

          def change_column_for_alter(table_name, column_name, type, **options)
            column = column_for(table_name, column_name)
            if options.has_key?(:null) && options[:null] == column.null
              options[:null] = nil
            end
            if type.to_sym == :virtual
              type = options[:type]
            end
            td = create_table_definition(table_name)
            cd = td.new_column_definition(column.name, type, **options)
            schema_creation.accept(cd)
          end

          # Bare-fragment helpers used only by `bulk_change_table`. AR core
          # defines methods of the same name with different return shapes
          # (a SchemaCreation node for default; a Proc-or-string sentinel
          # for null). These overrides intentionally diverge — keep them
          # private so AR core's contract is unaffected.
          # Both fragments include the column's SQL type to match the
          # non-bulk `change_column` shape (`MODIFY col TYPE …`); see the
          # ORA-02264 / Oracle 11g caveat documented on
          # `change_column_null_for_alter` below.
          def change_column_default_for_alter(table_name, column_name, default_or_changes) # :nodoc:
            column = column_for(table_name, column_name)
            default = extract_new_default_value(default_or_changes)
            "#{quote_column_name(column_name)} #{column.sql_type} DEFAULT #{quote(default)}"
          end

          # Returns nil when the requested nullability already matches the
          # column read from the data dictionary, so the dispatcher can
          # skip the MODIFY entirely.
          # Mirrors the redundancy guard `change_column` uses to avoid
          # ORA-01451 (already nullable) / ORA-01442 (already NOT NULL).
          # Includes the column's SQL type in the fragment to match the
          # non-bulk `change_column` path (`MODIFY col TYPE NOT NULL`);
          # the bare-column form `MODIFY col NOT NULL` triggers ORA-02264
          # on Oracle 11g (constraint-name auto-generation reuses an
          # existing implicit constraint name when the type is omitted).
          def change_column_null_for_alter(table_name, column_name, null, default = nil) # :nodoc:
            column = column_for(table_name, column_name)
            return nil if column.null == null
            "#{quote_column_name(column_name)} #{column.sql_type} #{null ? 'NULL' : 'NOT NULL'}"
          end

          # Returns true when the op needs the full `add_column` /
          # `change_column` path (not the bulk fragment) because those
          # methods issue extra SQL after the ALTER TABLE that the
          # column-only `*_for_alter` fragments do not reproduce:
          # - `comment:` -> a follow-up `COMMENT ON COLUMN`
          # - `:primary_key` type -> the `<table>_seq` sequence and, when
          #   `primary_key_trigger:` is true, the BEFORE INSERT trigger
          # - LOB types (text/ntext/binary/clob/nclob/blob) and any type
          #   with an explicit `tablespace:` option or a configured
          #   `default_tablespaces[type]` — `tablespace_for(...)` appends
          #   a TABLESPACE / LOB STORE clause that the bare column-fragment
          #   does not carry.
          def requires_full_command?(command, type, options)
            return true if options.key?(:comment)
            return true if command == :add_column && type.to_s.to_sym == :primary_key
            return true if needs_tablespace_clause?(type, options)
            false
          end

          LOB_TYPE_SYMBOLS = %i[text ntext binary clob nclob blob].freeze
          private_constant :LOB_TYPE_SYMBOLS

          def needs_tablespace_clause?(type, options)
            return true if options.key?(:tablespace)
            return false if type.nil?
            type_sym = type.to_s.to_sym
            return true if LOB_TYPE_SYMBOLS.include?(type_sym)
            return true if default_tablespaces.key?(type_sym)
            sql_type_sym = (type_to_sql(type).downcase.to_sym rescue nil)
            sql_type_sym && default_tablespaces.key?(sql_type_sym)
          end

          # True if a fragment targeting *this same* `column_name` is already
          # queued in `modify_buf`. Each fragment built by the `*_for_alter`
          # helpers starts with the quoted column name followed by a space,
          # so a prefix scan is enough. Used to avoid emitting
          # `MODIFY ("X" DEFAULT 1, "X" NOT NULL)` (ORA-00957).
          def column_in_modify_buf?(modify_buf, column_name)
            prefix = "#{quote_column_name(column_name)} "
            modify_buf.any? { |frag| frag.start_with?(prefix) }
          end

          # Returns true if pushing another fragment to `modify_buf` should
          # be preceded by a flush. Three triggers:
          # 1. `column_name` is queued in `add_buf` — `column_for` would not
          #    yet see the column, and the `MODIFY` would not be valid until
          #    the ADD commits.
          # 2. `column_name` is already in `modify_buf` — duplicate column
          #    references inside `MODIFY (...)` raise ORA-00957.
          # 3. Both `add_buf` and `modify_buf` are non-empty — Oracle 11g
          #    rejects `ALTER TABLE ADD (...) MODIFY (col1 ..., col2 ...)`
          #    (combined ADD with multi-column MODIFY) with ORA-02264, even
          #    though 12c+ accept it. Splitting forces single-column MODIFY
          #    when an ADD is in flight, which 11g handles cleanly.
          def needs_pre_modify_flush?(add_buf, modify_buf, add_pending, column_name)
            return true if add_pending.include?(quote_column_name(column_name))
            return true if column_in_modify_buf?(modify_buf, column_name)
            return true if add_buf.any? && modify_buf.any?
            false
          end

          # Pre-expand `:add_timestamps` / `:remove_timestamps` into the
          # underlying `:add_column` / `:remove_column` operations so the
          # streaming dispatcher folds them into the same `ADD (...)` /
          # `DROP (...)` buckets as ordinary column changes. Mirrors the
          # defaults `AbstractAdapter#add_timestamps` would have applied
          # (`null: false`, `precision: 6` when supported).
          def expand_bulk_timestamps(operations)
            operations.flat_map do |operation|
              command, args, block = operation
              case command
              when :add_timestamps
                table_name = args[0]
                # Strip `:comment` here — it is applied after the bulk
                # flush via `apply_column_comments` (Oracle has no inline
                # `COMMENT` in ADD); see #2739 for the non-bulk equivalent.
                options = args[1].is_a?(Hash) ? args[1].except(:comment) : {}
                options[:null] = false if options[:null].nil?
                options[:precision] = 6 if !options.key?(:precision) && supports_datetime_with_precision?
                [
                  [:add_column, [table_name, :created_at, :datetime, options], block],
                  [:add_column, [table_name, :updated_at, :datetime, options], block],
                ]
              when :remove_timestamps
                table_name = args[0]
                [
                  [:remove_column, [table_name, :updated_at], block],
                  [:remove_column, [table_name, :created_at], block],
                ]
              else
                [operation]
              end
            end
          end

          def collect_timestamps_comments(operations)
            operations.each_with_object([]) do |(command, args, _block), acc|
              next unless command == :add_timestamps
              options = args[1]
              next unless options.is_a?(Hash) && options.key?(:comment)
              acc << options[:comment]
            end
          end

          def flush_bulk_add_modify(table_name, add_buf, modify_buf)
            return if add_buf.empty? && modify_buf.empty?
            clauses = []
            clauses << "ADD (#{add_buf.join(', ')})" if add_buf.any?
            clauses << "MODIFY (#{modify_buf.join(', ')})" if modify_buf.any?
            execute "ALTER TABLE #{quote_table_name(table_name)} #{clauses.join(' ')}"
            add_buf.clear
            modify_buf.clear
          end

          def flush_bulk_drops(table_name, drop_buf)
            return if drop_buf.empty?
            remove_columns(table_name, *drop_buf)
            drop_buf.clear
          end

          def flush_bulk_buffers(table_name, add_buf, modify_buf, drop_buf)
            flush_bulk_add_modify(table_name, add_buf, modify_buf)
            flush_bulk_drops(table_name, drop_buf)
          end

          # Per-object-kind "does not exist" ORA codes used by `drop_if_exists`.
          MISSING_OBJECT_ORA_CODES = {
            "TABLE"             => "ORA-00942",
            "VIEW"              => "ORA-00942",
            "SEQUENCE"          => "ORA-02289",
            "PUBLIC SYNONYM"    => "ORA-01432",
            "SYNONYM"           => "ORA-01434",
            "MATERIALIZED VIEW" => "ORA-12003",
            "PROCEDURE"         => "ORA-04043",
            "FUNCTION"          => "ORA-04043",
            "PACKAGE"           => "ORA-04043",
            "TYPE"              => "ORA-04043",
            "TRIGGER"           => "ORA-04080",
            "INDEX"             => "ORA-01418",
          }.freeze
          private_constant :MISSING_OBJECT_ORA_CODES

          def missing_object_ora_code?(message, object_type)
            code = MISSING_OBJECT_ORA_CODES[object_type.to_s.upcase]
            code && message.include?(code)
          end

          def index_column_names(column_names) # :nodoc:
            column_names.is_a?(Array) ? column_names : Array(column_names)
          end

          def needs_unique_constraint?(unique, columns)
            return false unless unique
            Array(columns).none? { |column| column.to_s.include?("(") }
          end

          def add_unique_constraint_sql(table_name, columns, index_name)
            quoted_cols = Array(columns).map { |column| quote_column_name_or_expression(column) }.join(", ")
            "ALTER TABLE #{quote_table_name(table_name)} ADD CONSTRAINT #{quote_column_name(index_name)} UNIQUE (#{quoted_cols}) USING INDEX #{quote_column_name(index_name)}"
          end

          def add_inline_unique_constraints(table_name, td)
            td.indexes.each do |column_name, index_options|
              next unless needs_unique_constraint?(index_options[:unique], column_name)
              next unless OracleEnhancedAdapter.add_index_unique_creates_constraint
              warn_implicit_unique_constraint_deprecation
              inline_index_name = index_options[:name]&.to_s || index_name(table_name, column: index_column_names(column_name))
              execute add_unique_constraint_sql(table_name, column_name, inline_index_name)
            end
          end

          def warn_implicit_unique_constraint_deprecation
            OracleEnhanced.deprecator.warn(<<~MSG)
              add_index :col, unique: true creates an implicit named UNIQUE constraint on Oracle,
              in addition to the unique index. This implicit-constraint behavior will be removed
              in a future oracle-enhanced release.

              To silence this warning, set the flag in an initializer:

                ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.add_index_unique_creates_constraint = false

              After setting the flag, choose the path that matches your intent:

              * Unique INDEX only (typical when foreign keys reference primary keys):
                no migration changes needed — add_index :col, unique: true keeps creating
                the unique index, just without the extra UNIQUE CONSTRAINT.

              * Unique INDEX + UNIQUE CONSTRAINT (needed when this column is a non-PK
                foreign-key target, which Oracle only allows against named constraints):
                use add_unique_constraint instead — it creates both the constraint and
                its backing unique index in one call, e.g.

                  add_unique_constraint :sections, :position, name: :uniq_position
            MSG
          end

          def validate_identity_options!(identity, id, primary_key)
            return unless identity
            unless supports_identity_columns?
              raise ArgumentError,
                "`identity: true` requires Oracle Database 12.1 or higher (current: #{database_version}). Remove `identity: true` or upgrade the database."
            end
            unless id == :primary_key
              raise ArgumentError,
                "`identity: true` requires `id: :primary_key` (the default); got id: #{id.inspect}."
            end
            if primary_key.is_a?(Array)
              raise ArgumentError,
                "`identity: true` cannot be combined with a composite primary key."
            end
          end

          def validate_primary_key_trigger_options!(primary_key_trigger, identity, id, primary_key)
            return unless primary_key_trigger
            if identity
              raise ArgumentError,
                "`primary_key_trigger: true` cannot be combined with `identity: true`."
            end
            unless id == :primary_key
              raise ArgumentError,
                "`primary_key_trigger: true` requires `id: :primary_key` (the default); got id: #{id.inspect}."
            end
            if primary_key.is_a?(Array)
              raise ArgumentError,
                "`primary_key_trigger: true` cannot be combined with a composite primary key."
            end
          end

          def should_create_sequence?(td, id, identity)
            return false if identity
            numeric_pk_types = [:primary_key, :integer, :bigint, :decimal]
            if id
              numeric_pk_types.include?(id)
            else
              td.columns.any? do |column|
                column.options[:primary_key] && numeric_pk_types.include?(column.type)
              end
            end
          end

          def change_table_comment_sql(table_name, comment_or_changes)
            comment = extract_new_comment_value(comment_or_changes)
            if comment.nil?
              "COMMENT ON TABLE #{quote_table_name(table_name)} IS ''"
            else
              "COMMENT ON TABLE #{quote_table_name(table_name)} IS #{quote(comment)}"
            end
          end

          def change_column_comment_sql(table_name, column_name, comment_or_changes)
            comment = extract_new_comment_value(comment_or_changes)
            if comment.nil?
              "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} IS ''"
            else
              "COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} IS #{quote(comment)}"
            end
          end

          def insert_versions_sql(versions)
            formatter_class = ActiveRecord.schema_versions_formatter
            if formatter_class.equal?(ActiveRecord::Migration::DefaultSchemaVersionsFormatter)
              formatter_class = OracleEnhanced::SchemaVersionsFormatter
            end
            formatter_class.new(self).format(versions)
          end

          def extract_foreign_key_action(specifier)
            case specifier
            when "CASCADE"; :cascade
            when "SET NULL"; :nullify
            end
          end

          def extract_foreign_key_deferrable(deferrable, deferred)
            return false unless deferrable == "DEFERRABLE"
            deferred == "DEFERRED" ? :deferred : :immediate
          end

          def assert_valid_deferrable(deferrable)
            return if !deferrable || %i(immediate deferred).include?(deferrable)

            raise ArgumentError, "deferrable must be `:immediate` or `:deferred`, got: `#{deferrable.inspect}`"
          end

          def unique_constraint_name(table_name, **options)
            options.fetch(:name) do
              column_or_index = Array(options[:column] || options[:using_index]).map(&:to_s)
              identifier = "#{table_name}_#{column_or_index * '_and_'}_unique"
              hashed_identifier = OpenSSL::Digest::SHA256.hexdigest(identifier).first(10)

              "uniq_rails_#{hashed_identifier}"
            end
          end

          def unique_constraint_for(table_name, **options)
            name = unique_constraint_name(table_name, **options) unless options.key?(:column)
            unique_constraints(table_name).detect { |uc| uc.defined_for?(name: name, **options) }
          end

          def unique_constraint_for!(table_name, column: nil, **options)
            unique_constraint_for(table_name, column: column, **options) ||
              raise(ArgumentError, "Table '#{table_name}' has no unique constraint for #{column || options}")
          end

          def create_alter_table(name)
            OracleEnhanced::AlterTable.new create_table_definition(name)
          end

          def create_table_definition(name, **options)
            OracleEnhanced::TableDefinition.new(self, name, **options)
          end

          def new_column_from_field(table_name, field, definitions)
            limit, scale = field["limit"], field["scale"]
            if limit || scale
              field["sql_type"] += "(#{(limit || 38).to_i}" + ((scale = scale.to_i) > 0 ? ",#{scale})" : ")")
            end

            if field["sql_type_owner"]
              field["sql_type"] = field["sql_type_owner"] + "." + field["sql_type"]
            end

            is_virtual = field["virtual_column"] == "YES"
            is_identity = field["identity_column"] == "YES"

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

            type_metadata = OracleEnhanced::TypeMetadata.new(fetch_type_metadata(field["sql_type"]), virtual: is_virtual)
            default_value = extract_value_from_default(field["data_default"])
            default_value = nil if is_virtual || is_identity
            column_name = oracle_downcase(field["name"])
            trigger_assigned = trigger_assigned_pk_columns(table_name).include?(column_name)
            OracleEnhanced::Column.new(column_name,
                             lookup_cast_type(field["sql_type"]),
                             default_value,
                             type_metadata,
                             field["nullable"] == "Y",
                             comment: field["column_comment"],
                             identity: is_identity,
                             trigger_assigned: trigger_assigned
            )
          end

          def trigger_assigned_pk_columns(table_name)
            @trigger_assigned_pk_cache[table_name.to_s] ||= begin
              owner, desc_table_name = resolve_data_source_name(table_name.to_s)
              if trigger_backed_primary_key?(owner, desc_table_name)
                pks = primary_keys(table_name)
                pks.size == 1 ? pks : []
              else
                []
              end
            end
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
            default_tablespaces[type]
          end

          def column_for(table_name, column_name)
            unless column = columns(table_name).find { |c| c.name == column_name.to_s }
              raise "No such column: #{table_name}.#{column_name}"
            end
            column
          end

          def create_pk_sequence(table_name, options)
            seq_name = options[:sequence_name] || default_sequence_name(table_name, nil)
            seq_start_value = options[:sequence_start_value] || default_sequence_start_value
            execute "CREATE SEQUENCE #{quote_table_name(seq_name)} START WITH #{seq_start_value}"
          end

          def create_pk_trigger(table_name, pk_column, options)
            seq_name = options[:sequence_name] || default_sequence_name(table_name, nil)
            trigger_name = options[:trigger_name] || default_trigger_name(table_name)
            pk = pk_column || ActiveRecord::Base.get_primary_key(table_name.to_s.singularize)
            execute <<~SQL
              CREATE OR REPLACE TRIGGER #{quote_table_name(trigger_name)}
                BEFORE INSERT ON #{quote_table_name(table_name)} FOR EACH ROW
              BEGIN
                IF inserting THEN
                  IF :new.#{quote_column_name(pk)} IS NULL THEN
                    SELECT #{quote_table_name(seq_name)}.NEXTVAL INTO :new.#{quote_column_name(pk)} FROM dual;
                  END IF;
                END IF;
              END;
            SQL
          end

          def rename_pk_trigger(old_table_name, new_table_name)
            existing = trigger_backed_table_names[new_table_name.to_s.upcase]
            return unless existing

            pk_column = primary_keys(new_table_name).first
            return unless pk_column

            default_old = default_trigger_name(old_table_name).upcase
            if existing.upcase == default_old
              create_pk_trigger(new_table_name, pk_column, {})
              execute "DROP TRIGGER #{quote_table_name(existing)}" rescue nil
            else
              create_pk_trigger(new_table_name, pk_column, trigger_name: existing.downcase)
            end
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

          # Resolves an Oracle data-source name to its underlying [owner, table_name]
          # via DBMS_UTILITY.NAME_RESOLVE, which chases private and public
          # synonyms server-side in a single round trip. NAME_RESOLVE surfaces
          # circular synonym chains as ORA-00980 ("synonym translation is no
          # longer valid"), which we let propagate as
          # OracleEnhanced::ConnectionException.
          #
          # The PL/SQL call bypasses the adapter's select_one path, so we wrap
          # it in a sql.active_record SCHEMA notification to keep describe
          # visible to logging and instrumentation subscribers.
          def resolve_data_source_name(name)
            real_name = normalize_name_for_name_resolve(name)
            instrumenter.instrument(
              "sql.active_record",
              sql: "DBMS_UTILITY.NAME_RESOLVE(#{real_name.inspect}, 0, ...)",
              name: "SCHEMA",
              connection: self,
            ) do
              with_raw_connection(allow_retry: true) do |conn|
                conn.name_resolve(real_name)
              end
            end
          rescue OracleEnhanced::ConnectionException, ArgumentError
            raise
          rescue => e
            raise OracleEnhanced::ConnectionException,
                  %Q{"DESC #{name}" failed; does it exist? (#{e.message})}
          end

          # Normalize a data-source name for DBMS_UTILITY.NAME_RESOLVE.
          # NAME_RESOLVE uppercases unquoted identifiers, so mixed-case
          # identifiers like `test_Mixed` must be wrapped in double quotes to
          # preserve their case. Normalization is per-dotted-part: a valid
          # unquoted identifier (all upper, no spaces, etc.) is upcased in
          # place; any other part is wrapped in quotes. This lets
          # `sys.test_Mixed` become `SYS."test_Mixed"` rather than the
          # all-quoted `"sys"."test_Mixed"` (which would send Oracle hunting
          # for a lowercase schema and miss SYS).
          def normalize_name_for_name_resolve(name)
            name = name.to_s
            raise ArgumentError, "db link is not supported" if name.include?("@")

            limit = max_identifier_length
            return name.upcase if OracleEnhanced::Quoting.valid_table_name?(name, max_identifier_length: limit)

            parts = split_dotted_name(name)
            if parts.empty? || parts.any?(&:empty?) || parts.length > 2
              raise ArgumentError, "malformed identifier: #{name.inspect}"
            end

            parts.map do |part|
              if part.start_with?('"') && part.end_with?('"') && part.size >= 2
                part
              elsif part.start_with?('"') || part.end_with?('"')
                # Half-quoted: opens with `"` but never closes (or vice versa).
                # `Test"x` (embedded `"` mid-identifier) is allowed via the
                # quote-and-double-escape branch below; `"foo` is not.
                raise ArgumentError, "malformed identifier: #{name.inspect}"
              elsif OracleEnhanced::Quoting.valid_table_name?(part, max_identifier_length: limit)
                part.upcase
              else
                # Oracle quoted identifier syntax: an embedded `"` must be doubled.
                %("#{part.gsub('"', '""')}")
              end
            end.join(".")
          end

          # Splits a dotted Oracle name on `.` boundaries while leaving dots
          # that appear inside double-quoted identifiers untouched. Honours
          # the `""` escape sequence Oracle uses for an embedded `"` inside
          # a quoted identifier.
          def split_dotted_name(name)
            parts = []
            current = +""
            in_quotes = false
            i = 0
            while i < name.length
              char = name[i]
              if char == '"'
                if in_quotes && name[i + 1] == '"'
                  current << '""'
                  i += 2
                  next
                end
                in_quotes = !in_quotes
                current << char
              elsif char == "." && !in_quotes
                parts << current
                current = +""
              else
                current << char
              end
              i += 1
            end
            parts << current
            parts
          end

          # Splits "schema.identifier" into its parts, returning [schema, identifier].
          # Mirrors Rails' PostgreSQL/MySQL adapters: a non-qualified name yields
          # schema = nil. Oracle-specific bits: rejects db links and upcases valid
          # identifiers so catalog lookups match the stored upper-case names.
          def extract_schema_qualified_name(string)
            string = string.to_s
            raise ArgumentError, "db link is not supported" if string.include?("@")

            string = string.upcase if OracleEnhanced::Quoting.valid_table_name?(string, max_identifier_length: max_identifier_length)
            schema, identifier = string.split(".") if string.include?(".")
            [schema, identifier || string]
          end
      end
    end
  end
end
