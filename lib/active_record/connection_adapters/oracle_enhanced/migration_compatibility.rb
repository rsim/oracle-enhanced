# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module OracleEnhanced
      module MigrationCompatibility # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::Versioned

        # Thread-local key used by V8_1 to opt back into the legacy implicit-
        # constraint behavior. Encapsulated here so that the entire
        # MigrationCompatibility module — key included — can be removed in
        # one piece in Phase 3 of the deprecation (#2702) without leaving
        # observable state behind in `Thread.current`.
        IMPLICIT_UNIQUE_CONSTRAINT_KEY = :__oracle_enhanced_implicit_unique_constraint
        private_constant :IMPLICIT_UNIQUE_CONSTRAINT_KEY

        def self.implicit_unique_constraint_enabled?
          Thread.current[IMPLICIT_UNIQUE_CONSTRAINT_KEY] == true
        end

        def self.with_implicit_unique_constraint_enabled
          prev = Thread.current[IMPLICIT_UNIQUE_CONSTRAINT_KEY]
          Thread.current[IMPLICIT_UNIQUE_CONSTRAINT_KEY] = true
          yield
        ensure
          Thread.current[IMPLICIT_UNIQUE_CONSTRAINT_KEY] = prev
        end

        # Phase 2 of the implicit-UNIQUE-CONSTRAINT deprecation (#2702):
        # `Migration[8.2]+` (the current default) treats `add_index unique:
        # true` as "create only the unique index" — matching the Rails-core
        # PostgreSQL/MySQL/SQLite adapters. `Migration[8.1]` and earlier
        # opt back into the pre-Phase-2 behavior of also creating a
        # same-named UNIQUE CONSTRAINT, so existing migrations keep
        # working unchanged. Callers that need a constraint should call
        # `add_unique_constraint :t, :col, name: :n` directly.
        module V8_1
          def add_index(table_name, column_name, **options)
            MigrationCompatibility.with_implicit_unique_constraint_enabled { super }
          end

          def create_table(table_name, **options, &block)
            MigrationCompatibility.with_implicit_unique_constraint_enabled { super }
          end
        end
      end
    end
  end
end
