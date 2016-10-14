## 1.7.4 / 2016-10-14

* Changes and bug fixes

 * Bump Arel 7.1.4 or higher [#1010, #848, #946]
 * NoMethodError: undefined method `write' for nil:NilClass for serialized column [#798, #1007]
 * Quote table name in disable_referential_integrity [#1012, #1014]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438, rails/arel#450]
 * Add UPGRADE section : Upgrade Rails 4.2 or older version to Rails 5 [#1011, #993]
 * add docker to RUNNING_TEST.md [#1006]
 * Add executable test cases using Minitest or RSpec [#1002]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
    * Workaround: execute explain without bind or use CRuby
 - CRuby and JRuby
 * Rails 5 : custom methods for create record when exception is raised in after_create callback fails [#944]
 * Rails 5 : specs need update to emulate_booleans_from_strings [#942]
 * #998 causes regression for `TIMESTAMP WITH LOCAL TIME ZONE` [#1001]

## 1.7.3 / 2016-10-03

* Changes and bug fixes
 * Respect `ActiveRecord::Base.default_timezone = :utc` rather than connection `time_zone` value [#755, #998]

* Known issues
 * No changes since 1.7.0.rc1

## 1.7.2 / 2016-09-19

* Changes and bug fixes
 * Remove ruby-oci8 from runtime dependency [#992,#995]
 * Update README to add `gem 'ruby-oci8'` explicitly for CRuby users [#992, #995]

* Known issues
 * No changes since 1.7.0.rc1

## 1.7.1 / 2016-08-22

* Changes and bug fixes
 * Add `ActiveRecord::OracleEnhanced::Type::Boolean` [#985, #979]
 * Address `create_table': undefined method `each_pair' for []:Array (NoMethodError) [#980]
 * Deprecate `fallback_string_to_date`, `fallback_string_to_time` [#974]

* Known issues
 * No changes since 1.7.0.rc1

## 1.7.0 / 2016-08-04

* Changes and bug fixes
 * No changes since 1.7.0.rc1

* Known issues
 * No changes since 1.7.0.rc1

## 1.7.0.rc1 / 2016-08-02

* Changes and bug fixes

 * Support `emulate_booleans_from_strings` in Rails 5 [#953, #942]
 * Deprecate `self.is_boolean_column?` [#949]
 * Deprecate `self.is_date_column?` and `is_date_column?` [#950]
 * Deprecate `set_type_for_columns`, `set_type_for_columns` and `clear_types_for_columns` [#951]
 * Deprecate `self.is_integer_column?` [#952]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
    * Workaround: execute explain without bind or use CRuby
 - CRuby and JRuby
 * Rails 5 : custom methods for create record when exception is raised in after_create callback fails [#944]
 * Rails 5 : specs need update to emulate_booleans_from_strings [#942]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]
    * #848 reproduces when database version is 11gR2 or older, it does not reproduce with 12c
    * One of the units test skipped when database version is 11gR2 or lower. [#946]

## 1.7.0.beta7 / 2016-08-01

* Changes and bug fixes

 * Use OracleEnhanced::SchemaDumper#tables and #table
   only if they have Oracle enhanced specific features [#947, #797]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : custom methods for create record when exception is raised in after_create callback fails [#944]
 * Rails 5 : emulate_booleans_from_strings support [#942]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]
    * #848 reproduces when database version is 11gR2 or older, it does not reproduce with 12c
    * One of the units test skipped when database version is 11gR2 or lower. [#946]

## 1.7.0.beta6 / 2016-07-29

* Changes and bug fixes

 * Use attributes.keys to update all attributes when partial_write is disabled [#906 #943]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : custom methods for create record when exception is raised in after_create callback fails [#944]
 * Rails 5 : emulate_booleans_from_strings support [#942]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]
    * #848 reproduces when database version is 11gR2 or older, it does not reproduce with 12c

## 1.7.0.beta5 / 2016-07-28

* Changes and bug fixes

 * Use binds.size to set returning_id_index for returning_id [#907, #912 and #939]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : custom methods for create, update and destroy not working [#906]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]
    * #848 reproduces when database version is 11gR2 or older, it does not reproduce with 12c

## 1.7.0.beta4 / 2016-07-27

* Changes and bug fixes

 * Call `bind_returning_param` when sql has returning_id and using JRuby [#937]
 * Remove unused `col_type` to avoid warnings [#934]
 * Remove TODO comment since Oracle DATE type can be mapped Rails Datetime with attribute API [#935]
 * Remove rspec from runtime dependency [#933]
 * Rename `add_dependency` to `add_runtime_dependency` [#933]
 * Remove warnings for + when tested with JRuby 9.1.2 [#936]

* Known issues

 - Only with JRuby
 * Rails 5 : create table with primary key trigger with default primary key not returning id [#912]
    * #937 addresses two failures reported in #912
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : create table with primary key trigger not returning id [#907]
 * Rails 5 : custom methods for create, update and destroy not working [#906]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]

## 1.7.0.beta3 / 2016-07-22

* Changes and bug fixes
 * Not giving `bind_param` a 3rd argument `column` [#929, #909]

* Known issues

 - Only with JRuby
 * Rails 5 : create table with primary key trigger with default primary key not returning id [#912]
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : create table with primary key trigger not returning id [#907]
 * Rails 5 : custom methods for create, update and destroy not working [#906]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]

## 1.7.0.beta2 / 2016-07-22

* Changes and bug fixes

 * Support CLOB for JRuby [#926, #910, #911]
 * Arel 7.1.0 or higher version is required [#919]
 * Document usage of ActiveRecord Attributes API in 1.7 [#924]
 * Add a note about usage pecularities of context_index's index_column option to README [#924]
 * Set required_ruby_version = '>= 2.2.2' [#916]
 * Remove ActiveRecord::ConnectionAdapters::TableDefinition#aliased_types [#921]
 * Update warning message for composite primary keys [#923]
 * Remove specs deprecated in Oracle enhanced adapter 1.7 [#917]
 * Rails 5 : has_and_belongs_to_many test gets ORA-01400 since primary key column "ID"
    not included in insert statement [#856, rails/rails#25388, rails/rails#25578 ]
   - This fix will be included in the next version of Rails which should be named 5.0.1

* Known issues

 - Only with JRuby
 * Rails 5 : create table with primary key trigger with default primary key not returning id [#912]
 * Rails 5 : SQL with bind parameters when NLS_NUMERIC_CHARACTERS is set to ', '
    show Java::JavaSql::SQLSyntaxErrorException: / ORA-01722: invalid number [#909]
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : create table with primary key trigger not returning id [#907]
 * Rails 5 : custom methods for create, update and destroy not working [#906]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]

## 1.7.0.beta1 / 2016-07-18

* Major enhancements

 * Support Rails 5.0
 * Use Arel::Visitors::Oracle12 to use better top-N query support [#671]
 * Oracle TIMESTAMP sql type is associated with Rails `DateTime` type [#845]
 * Rails :time as Oracle TIMESTAMP to support subsecond precision [#817, #816]
 * Rails :datetime as Oracle TIMESTAMP to support subsecond precision [#739]
 * Remove ActiveRecord::OracleEnhanced::Type::Timestamp [#815]
 * Deprecate `quote_date_with_to_date` and `quote_timestamp_with_to_timestamp` [#879]
 * Deprecate `set_boolean_columns` and `set_string_columns` [#874]
 * Deprecate `set_integer_columns [#872]
 * Deprecate `set_date_columns` and `set_datetime_columns` [#869]
 * Deprecate `ignore_table_columns` to use Rails native `ignored_columns` [#855]
 * Set :datetime for an attribute explicitly [#875, #876]
 * Support `#views` #738
 * Replace `table_exists?` with `data_source_exists?` [#842]
 * Introduce `data_source_exists?` to return tables and views [#841]
 * Implement primary_keys to prepare dumping composite primary key [#860]
 * Support for any type primary key [#836]
 * Dump composite primary keys [#863]
 * Dump type and options for non default primary keys [#861]
 * Support creating foreign keys in create table [#862]
 * Support ActiveRecord native comment feature [#822, #821, #819]

* Changes and bug fixes

 * Fix cast_type issue [#795]
 * Rename quote_value to quote_default_expression [#661]
 * Change bind parameters order to come offset first then limit next [#831]
 * type_cast arity change [#781]
 * Initial support for sql_type_metadata [#656]
 * Support bind_params for JDBC connections [#806]
 * Use all_* dictionary replacing user_* ones [#713]
 * Register `NUMBER(1)` sql_type to `Type::Boolean` [#844]
 * Add `ActiveRecord::ValueTooLong` exception class [#827]
 * Not passing `native_database_types` to `TableDefinition` [#747]
 * Ignore index name in `index_exists?` when not passed a name to check for [#840]
 * Add reversible syntax for change_column_default [#839]
 * Support Oracle national character set NCHAR, NVARCHAR2 [#886]
 * Support "limited" :returning_id [#894, #803]
 * Support RAW sql data type in Rails 5 [#877]
 * Remove `serialized_attributes` which is removed in Rails 5 [#694]
 * Add deprecation warning for `bind_param` [#809]
 * Remove `self.string_to_raw` from Column which is not called anymore [#813]
 * Remove type_cast from Column [#811]
 * Remove deprecated `distinct` method [#771]
 * Remove alias_method_chain and rename oracle_enhanced_table to table [#864]
 * Warn if `AR.primary_key` is called for a table with composite primary key [#837]
 * Remove select method from Oracle enhanced adapter [#784]
 * Remove version check to see if ::Rails::Railtie exists [#769]
 * Remove FALSE_VALUES [#716]
 * Remove TRUE_VALUES from OracleEnhancedColumn [#646]
 * Remove insert_sql method [#866, #890]
 * Rails5 remove require bind visitor [#853]
 * substitute_at has been removed from Rails [#849]
 * Serialize value for lob columns [#878]
 * Do not cache prepared statements that are unlikely to have cache hits [#748]
 * Handle BLOB type correctly [#804]
 * Move ActiveRecord::Type to ActiveModel [#723]
 * Remove cast_type to support Rails 5 Attribute API [#867]
 * Handle ActiveModel::Type::Binary::Data type cast in _type_cast [#826]
 * Use Abstract adapter `dump_schema_information` implementation [#857]
 * Use ActiveRecord initialize_schema_migrations_table [#843]
 * Use ActiveRecord::SchemaDumper#ignored? [#838]
 * Use Abstract adapter join_to_update [#801, #800]
 * Use ActiveRecord::OracleEnhanced::Type::Text [#887]
 * Use ActiveRecord::OracleEnhanced::Type::String [#883]
 * Use OracleEnhanced::ColumnDefinition [#650]
 * Move to ActiveRecord::ConnectionAdapters::OracleEnhanced::SchemaDumper [#695]
 * ColumnDumper uses Module#prepend [#696]
 * Migrate from OracleEnhancedSchemaStatementExt to OracleEnhanced::SchemaStatementsExt [#768]
 * Extract ActiveRecord::ConnectionAdapters::OracleEnhanced::Quoting [#764]
 * Use keyword arguments for new table options [#820]
 * Move `ruby_to_java_value` logic to `_type_cast` [#904]
 * OracleEnhancedColumn.new needs sql_type_metadata including sql_type [#858]
 * OracleEnhanced::JDBCQuoting and OCIQuoting [#897]
 * Address `add_column_options!': undefined method `quote_value' [#647]
 * Remove dirty tracking methods [#883]
 * Use arel master branch for rails5 development [#645]
 * Bump ruby-oci8 version to 2.2.0 or higher [#775] 
 * Remove jeweler dependency [#766]
 * Remove required_rubygems_version [#719]
 * Remove journey which is already part of Rails [#701]
 * Remove dependencies with non activerecord gems [#700]
 * Remove activerecord-deprecated_finders [#698]
 * Use rack master branch [#697]
 * Clean up gemspec file and bump rspec, ruby-plsql and ruby-oci8 versions [#717]
 * Remove magic comment for utf-8 [#772, #726]
 * add_dependency with ruby-oci8 only if it runs cruby, not jruby [#902]
 * Install ruby-debug for jruby [#899]
 * Address dirty object tracking should not mark empty text as changed [#888]
 * Revert "Update matcher to skip sql statements to get `table` metadata" [#881]
 * No need to set @visitor instance variable here [#854]
 * log binds should not be type_casted [#818]
 * Fix schema dumper errors [#810]
 * Address undefined method `cast_type' [#805]
 * Better fix to support "Relation#count does not support finder options anymore in Rails [#788, #787]
 * ActiveRecord::Calculations#count no longer accepts an options hash argument #754
 * Supress WARNINGs using `raise_error` without specific errors [#724]
 * Use RSpec 3 [#707]
 * Update "OracleEnhancedAdapter boolean type detection based on string column types and names" [#873]
 * Update "OracleEnhancedAdapter integer type detection based on column names" [#871]
 * Update "OracleEnhancedAdapter date type detection based on column names" [#868]
 * Do not set emulate_dates_by_column_name or emulate_dates in specs [#870]
 * Update rake spec message to show default branch name as master [#648]
 * Remove `ActiveRecord::Base.default_timezone = :local` from spec_helper [#901]
 * Update to rspec3 syntax to avoid deprecation notices [#776]
 * Remove RAILS_GEM_VERSION [#702]
 * Run Oracle enhanced adapter unit tests using Travis CI [#789]
 * Upgrade travis-oracle to Version 2.0.1 [#903]

* Known issues

 - Only with JRuby
 * Rails 5 : create table with primary key trigger with default primary key not returning id [#912]
 * Rails 5 : dirty object tracking not working correctly for CLOB [#911]
 * Rails 5 : handling of CLOB columns get failures [#910]
 * Rails 5 : SQL with bind parameters when NLS_NUMERIC_CHARACTERS is set to ', ' 
    show Java::JavaSql::SQLSyntaxErrorException: / ORA-01722: invalid number [#909]
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
 - CRuby and JRuby
 * Rails 5 : create table with primary key trigger not returning id [#907]
 * Rails 5 : custom methods for create, update and destroy not working [#906]
 * Rails 5 : has_and_belongs_to_many test gets ORA-01400 since primary key column "ID" 
    not included in insert statement [#856, rails/rails#25388]
 * Rails 5 : undefined method `to_i' for #<Arel::Nodes::BindParam:0x00000002c92910> [#848, rails/arel#438]

## 1.6.7 / 2016-03-08

* Changes and bug fixes since 1.6.6
 * Support Rails 4.2.6
 * Support t.foreign_key use the same `to_table` twice [#783]
 * Remove "warning: (...) interpreted as grouped expression" [#765]
 * Add documentation on setting read, write and connect timeouts [#761]

## 1.6.6 / 2016-01-21

* Changes and bug fixes since 1.6.5
 * Address ORA-00904 when CONTAINS has `table_name.column_name` [#758, #664, #463]
 * Only convert N to false when emulating booleans [#751]
 * Clean up specs and test documentation [#756]
 * Add JDBC Drivers to gitignore [#745]

## 1.6.5 / 2015-12-01

* Enhancement
 * Support `schema` option to use schema objects owned by another schema[#742]

## 1.6.4 / 2015-11-09

* Changes and bug fixes since 1.6.3
 * Add table and column comments to structure dump and schema dump [#734]
 * Remove `serialized_attributes` which is removed in Rails 5 [#694]
 * fixing bundler dependency conflict with head of rails vs arel 6.0[#714]
 * Add note to readme about adapter name when using DATABASE_URL [#728]
 * Fixed copy/paste error in README.md [#731]
 * Pending a test using virtual columns features introduced in 11gR1 [#733]
 * Suppress warning: ambiguous first argument [#690]
 * Suppress `warning: assigned but unused variable` [#691]
 * Suppress `warning: assigned but unused variable - tablespace` [#692]
 * Suppress `warning: assigned but unused variable - e` [#693]
 * Ignore .rbenv-gemsets [#705]
 * Clean up database objects after unit tests executed [#712]

## 1.6.3 / 2015-08-14

* Changes and bug fixes since 1.6.2
 * Set sequence name automatically when new table name is longer than 26 bytes[#676]
 * Add minimal specs for ActiveRecord::Base.limit() and .order()[#679]
 * Use type_casted_binds [#681]
 * Use type_cast_for_database to serialize correctly [#688]
 * Suppress deprecated message for serialized_attributes [#688, #548, #687]

## 1.6.2 / 2015-07-20

* Changes and bug fixes since 1.6.1

 * Oracle enhanced adapter v1.6 requires ActiveRecord 4.2.1 or higher,
   ActiveRecord 4.2.0 is not supported.[#672]
 * Unique constraints not created when function unique index created [#662, #663]
 * create_table should use default tablespace values for lobs [#668]

## 1.6.1 / 2015-07-01

* Changes and bug fixes since 1.6.0

 * Oracle enhanced adapter v1.6 requires ActiveRecord 4.2.1 or higher, 
   ActiveRecord 4.2.0 is not supported.[#651, #652]
 * Fix serialized value becomes from yaml to string once saved [#655, #657]
 * Update Ruby version in readme [#654]
 * Update unit test matcher to skip sql statements to get `table` metadata [#653] 

## 1.6.0 / 2015-06-25

* Changes and bug fixes since 1.6.0.beta1

 * Add deprecation warnings for Oracle enhanced specific foreign key methods [#631]
 * Skip composite foreign key tests not supported in this version [#632]
 * Do not dump default foreign key name [#633]
 * Schema dump uses `:on_delete` option instead of `:dependent` [#634]
 * Use Rails foreign key name in rspec unit tests [#635]
 * Add deprecate warning if foreign key name length is longer than 30 byte [#636]
 * Foreign key name longer than 30 byte will be shortened using Digest::SHA1.hexdigest [#637]
 * Schema dumper for :integer will not dump :precision 0 [#638]
 * Update foreign key names for add_foreign_key with table_name_prefix [#643]

* Known Issues since 1.6.0.beta1
 * table_name_prefix and table_name_suffix changes column names which cause ORA-00904 [#639]
 * custom methods should rollback record when exception is raised in after_create callback fails [#640]
 * custom methods for create, update and destroy should log create record fails [#641]

## 1.6.0.beta 1 / 2015-06-19

* Enhancements
 * Support Rails 4.2
 * Support Rails native foreign key syntax [#488, #618]

* Other changes and bug fixes
 * Column#primary method removed from Rails [#483]
 * ActiveRecord::Migrator.proper_table_name has been removed from Rails [#481]
 * New db/schema.rb files will be created with force: :cascade [#593]
 * Rails42 add unique index creates unique constraint [#617]
 * Modify remove_column to add cascade constraint to avoid ORA-12991 [#617]
 * Add `null: true` to avoid DEPRECATION WARNING [#489, #499]
 * Rails 4.2 Add `connection.supports_views?` [#496]
 * text? has been removed from Column class [#487]
 * Remove call to deprecated `serialized_attributes` [#550, #552]
 * Support :cascade option for drop_table [#579]
 * Raise a better exception for renaming long indexes [#577]
 * Override aliased_types [#575]
 * Revert "Add options_include_default!" [#586]
 * Remove substitute_at method from Oracle enhanced adapter [#520]
 * Require 'active_record/base' in rake task #526
 * Make it easier to spot which version of active record is actually used [#550]
 * Rails4.2 Add Type::Raw type [#503]
 * Support :bigint datatype [#580]
 * Map :bigint as NUMBER(19) sql_type not NUMBER(8) [#608]
 * Use Oracle BINARY_FLOAT datatype for Rails :float type [#610]
 * Revert "Implement possibility of handling of NUMBER columns as :float" [#576]
 * Rails 4.2 Support NCHAR correctly [#490]
 * Support :timestamp datatype in Rails 4.2 [#575]
 * Rails 4.2 Handle NUMBER sql_type as `Type::Integer` cast type [#509]
 * ActiveRecord::OracleEnhanced::Type::Integer for max_value to take 38 digits [#605]
 * Rails 4.2 add `module OracleEnhanced` and migrate classes/modules under this [#584]
 * Migrate to ActiveRecord::ConnectionAdapters::OracleEnhanced::ColumnDumper [#597]
 * Migrated from OracleEnhancedContextIndex to OracleEnhanced::ContextIndex [#599]
 * Make OracleEnhancedIndexDefinition as subclass of IndexDefinition [#600]
 * Refactor add_index and add_index_options [#601]
 * Types namespace moved to `ActiveRecord::Type::Value` [#484]
 * Add new_column method [#482]
 * Rename type_cast to type_cast_from_database [#485]
 * Removed `forced_column_type` by using `cast_type` [#595]
 * Move dump_schema_information to SchemaStatements [#611]
 * Move OracleEnhancedIndexDefinition to OracleEnhanced::IndexDefinition [#614]
 * Move OracleEnhancedSynonymDefinition to OracleEnhanced::SynonymDefinition [#615]
 * Move types under OracleEnhanced module [#603]
 * Make OracleEnhancedForeignKeyDefinition as subclass of ForeignKeyDefinition [#581]
 * Support _field_changed argument changes [#479]
 * Rails 4.2 Don't type cast the default on the column [#504]
 * Rename variable names in create_table to follow Rails implementation [#616]
 * Rails 4.2: Fix create_savepoint and rollback_to_savepoint name [#497]
 * Shorten foreign key name if it is longer than 30 byte [#621]
 * Restore foreign_key_definition [#624]
 * Rails 4.2 Support OracleEnhancedAdapter.emulate_integers_by_column_name [#491]
 * Rails 4.2 Support OracleEnhancedAdapter.emulate_dates_by_column_name [#492]
 * Rails 4.2 Support emulate_booleans_from_strings and is_boolean_column? [#506]
 * Rails 4.2 Support OracleEnhancedAdapter.number_datatype_coercion [#512]
 * Rails 4.2 Use register_class_with_limit [#502]
 * Rails 4.2 Remove redundant substitute index when constructing bind values [#517]
 * Rails 4.2 Unit test updated to support `substitute_at` in Arel [#522]
 * Change log method signiture to support Rails 4.2 [#539]
 * Enable loading spec configuration from config file instead of env [#550]
 * Rails42: Issue with non-existent columns [#545, #551]
 * Squelch warning "#column_for_attribute` will return a null object 
   for non-existent columns in Rails 5. Use `#has_attribute?`" [#551]
 * Use arel 6-0-stable [#565]
 * Support 'Y' as true and 'N' as false in Rails 4.2 [#574, #573]
 * Remove alias_method_chain :references, :foreign_keys [#582]
 * Use quote_value method to avoid undefined method `type_cast_for_database' for nil:NilClass [#486]
 * Rails 4.2: Set @nchar and @object_type only when sql_type is true [#493]
 * Rails 4.2: Handle forced_column_type temporary [#498]
 * Rails 4.2 Address ArgumentError: wrong number of arguments (1 for 2) at `quote_value` [#511]
 * Address ORA-00932: inconsistent datatypes: expected NUMBER got DATE [#538]
 * Remove duplicate alias_method_chain for indexes [#560]
 * Address RangeError: 6000000000 is out of range for ActiveRecord::Type::Integer 
   with limit 4 [#578]
 * Return foreign_keys_without_oracle_enhanced when non Oracle database used [#583]
 * Add missing database_tasks.rb to gemspec [#585]
 * Fixed typo in the rake tasks load statement [#587]
 * Call super when column typs is serialized [#563, #591]
 * Clear query cache on rollback [#592]
 * Modify default to `false` if database default value is "N" [#596]
 * refer correct location if filess in gemspec [#606]
 * Add integer.rb to gemspec [#607]

* Known Issues
 * Override aliased_types [#575]
 * Multi column foreign key is not supported

## 1.5.6 / 2015-03-30

* Enhancements
 * Support Rails 4.1.10 [#530]
 * Remove warning message when JDK 8 is used [#525]
 * Support RAW column types [#471]
 * Properly quote database links [#556]
 * Grant create view privilege to db user [#528]
 * Read SYSTEM password from ENV ORACLE_SYSTEM_PASSWORD optionally [#529]
 * Show original error message when loading ruby-oci8 library fails [#532]
 * Update README that `OracleEnhancedProcedures` is not auto loaded [#474]
 * Fix legacy schema support syntax [#507]
 * Peform all unit test when tested with Oracle 12c [#465]
 * Add `:if_exists` option to `drop_table` [#541]
 * Extract OracleEnhancedDatabaseStatements [#449]
 * Removed self.visitor_for(pool) method [#501]

* Bug Fix
 * Fix serialized readonly lobs [#515]
 * Do not dump schema information during structure dump [#558]
 * Structure dump generates correct create or replace synonym [#453]
 * Procedures and functions are created correctly by removing semi-colon [#456]
 * Show support matrix of Java and JDBC Driver only when java_version >= '1.8' [#455]
 * Update Gemfile dependencies so specs can run [#472]

## 1.5.5 / 2014-05-23

* Enhancements
 * Oracle NUMBER datatype can be handled as Rails :float datatype [#418]
   - Default NUMBER datatype handled as :decimal to keep compatibility
   - Configured by setting `self.number_datatype_coercion = :float` 
 * Add link to supported Oracle database version, JDK and Oracle JDBC Driver version [#438]
 * Support `without_prepared_statements?` to handle `unprepared_statement` [#447]

* Bug Fix
  * Associations with name `record` do not work correctly since Rails 4 [#435]
  * Skip another Oracle Text test when Oracle 12c used [#437]
  * Tag bind params with a bind param object [#444]

## 1.5.4 / 2014-03-25

* Enhancements
 * Support Rails 4.1.0.rc2
 * Allow Java 8 to run with jruby [#383]

* Bug Fix
  * Fix db:schema:dump when foreign key column name is not 'id' [#409]
  * Fix schema dump works when non Oracle adapter used [#428]

## 1.5.3 / 2014-03-04

* Enhancements
 * Supports Rails 4.1.0.rc1
 * Support rails/rails#13886 by chainging select_rows arguments [#415]

* Bug Fix
  * Fix ORA-01008: not all variables bound [#422]

## 1.5.2 / 2014-01-24

* Enhancements
 * Supports Rails 4.1.0.beta1
 * Support Rails 4 Database Tasks [#404]
 * Create sequence when add primary_key column [#406]
 * Move `SchemaCreation` to its own file [#381]
 * Remove unused OracleEnhancedColumnDefinition [#382]
 * Log bind variables after they were type casted [#385]
 * Remove add_order_by_for_association_limiting! [#388]
 * Support named savepoints [#389]
 * Support self.extract_value_from_default [#395]
 * Remove oracle_enhanced_core_ext.rb [#397]
 * Remove unused to_sql_with_foreign_keys and lob_columns [#398]
 * Remove ruby-oci8 v1 code [#405]

* Bug Fix
  * Move add_column_options! into SchemaCreation class [#384]
  * Add options_include_default! [#384]
  * Use OCI8::Metadata::Base#obj_link [#399]

## 1.5.1 / 2013-11-30

* Enhancements
 * Removed set_table_name set_primary_key set_sequence_name from unit tests [#364]
 * Update README to support assignment methods [#365]
 * Remove add_limit_offset! method [#369]
 * Update Gemfile to use `bundle config --local` [#370]
 * `describe` does not try super when no datbase link and ORA-4043 returned [#375]
 * Support `remove_columns` [#377]
 * Dump views in alphabetical order and add `FORCE` option [#378]

* Bug Fix
 * Fixed reverting add_column fails with v1.5.0 [#373]

## 1.5.0 / 2013-11-01

* Enhancements
 * Add license in gemspec and Rakefile [#361]

## 1.5.0.rc1 / 2013-10-31

* Update README and HISTORY
* No other changes since 1.5.0.beta1

## 1.5.0.beta1 / 2013-10-28

* Enhancements and major changes
 * Support Rails 4.0
 * Desupport Rails 3.2 and lower version. To support Rails 3.2, use Version 1.4.3
 * Drop session store support [#219]
 * Create indexes automatically for references and belongs_to [#183]
 * Use the index name explicitly provided in a migration when reverting [#296]
 * Rename indexes when a table or column is renamed [#286]
 * Support refactored remove_column [#172] 
 * Support allowed_index_name_length method [#285]
 * Remove schema prefix from sequence name if present before truncating [#155]
 * Bumped jeweler, ruby-plsql and ruby-oci8 version [#176]
 * Support also ojdbc6.jar for Java 1.7 [#350]
 * Support "activerecord-deprecated_finders" [#210]
 * Prepared statements can be disabled [#295]
 * Ensure disconnecting or reconnecting resets the transaction state [#220]
 * Support for specifying transaction isolation level [#226]
 * Rename the partial_updates config to partial_writes [#234]
 * Deprecate passing a string as third argument of add_index [#242]
 * Rename update method to update_record, create method to create_record [#273]
 * Deprecate #connection in favour of accessing it via the class [#297]
 * Support SchemaCreation [#298]
 * Add support for foreign key creation in create_table [#317]
 * Add virtual columns support for rail4 branch [#329]
 * Support columns_for_distinct method [#340]
 * Clear index cache when any table dropped [#200]
 * Clear index cache when remove_column executed [#269]
 * Dump schema uses ruby 1.9 style hash [#229]
 * Support _field_changed? and drop field_changed? [#182 #254]
 * Use arel nodes instead of raw sql [#198]
 * Raise an ArgumentError when passing an invalid option to add_index [#242]
 * Split OracleEnhancedColumnDumper from OracleEnhancedSchemaDumper [#292]
 * Unit test sets default_timezone = :local [#184]
 * Support reset_pk_sequence! [#287]
 * Remove unnecessary pendings in unit tests [#358]

* Bug Fix
 * Address ArgumentError: wrong number of arguments (5 for 3) [#166]
 * Address NoMethodError: undefined method `column_types' [#173]
 * Schema dumper removes table_name_prefix and table_name_suffix [#191]
 * Add clear_logger to address ArgumentError: wrong number of arguments (1 for 2) [#193]
 * Use Relation#to_a as Relation#all is deprecated in Rails [#203]
 * Address Address test_integer_zero_to_integer_zero_not_marked_as_changed failure [#207]
 * Address NoMethodError undefined method `default_string' [#221]
 * Address you can't redefine the primary key column 'id'. To define a custom primary key, pass { id: false } to create_table [#238]
 * Remove unnecessary DEPRECATION WARNING [#255]
 * Assigning "0.0" to a nullable numeric column does not make it dirty [#293]
 * Address `rake spec` abort [#353]
 * Correct activerecord-deprecated_finders not loaded if ENV['RAILS_GEM_VERSION'] set [#353]

* Known Issues
 * Oracle Text features are not fully supported with Oracle 12c [#331]

### 1.4.3 / 2013-10-24

* No changes since 1.4.3.rc2

### 1.4.3.rc2 / 2013-10-23

* Change build procedures
* No other changes since 1.4.3.rc1

### 1.4.3.rc1 / 2013-10-19

* Enhancements:
  * Allow inserting NULL to Oracle Spatial Data Types such as MDSYS.SDO_GEOMETRY [#311]
  * Support ojdbc7.jar JDBC Driver [#335]

* Bug fixes:
  * Fixed Gemfile to bundle update work [#294]
  * Fixed broken links in README.md and RUNNING_TESTS.md [#303 #306]
  * Address rename_table works if the source table created with :id => false [#336]
  * Use expand_path to show VERSION with Windows XP

### 1.4.2 / 2013-03-18

* No changes since 1.4.2.rc2

### 1.4.2.rc2 / 2013-03-01

* Bug fixes:
  * Do not consider the numeric attribute as changed if the old value is zero and the new value is not a string [#247]
  * Removed table_name_prefix and table_name_suffix when schema dumper executed [#248]
  * Remove_column should raise an ArgumentError when no columns are passed [#246]
  * Don't dump type for NUMBER virtual columns [#256]
  * Address :returning_id column should be of type Column [#274]
  * Migrated versions should be dumped in order [#277]
  * Always write serialized LOB columns [#275]
  * Truncate the schema_migrations index [#276]
  * Split paths on windows machines in the right way [#231]

### 1.4.2.rc1 / 2012-11-13

* Enhancements:
  * Wordlist option for context index [#154]
  * Fall back to directly connecting via OracleDriver on JRuby [#163]
  * Allow slash-prefixed database name in database.yml for using a service [#201]
* Bug fixes:
  * Fixed explain plans to work with JDBC and OCI8 [#146]
  * Fixed various issues with virtual columns [#159]
  * Fixed SQL structure dump with function indexes [#161]
  * Fixed broken column remove inside a change_table block [#216]
  * Dump indexes on virtual columns using the column's name instead of the column expression [#211]
  * Don't update lobs that haven't changed or are attr_readonly [#212]
  * Support dirty tracking with rails 3.2.9

### 1.4.1 / 2012-01-27

* Enhancements:
  * Support for Rails 3.2
  * Support for ActiveRecord 3.2 explain plans [#116]
  * Support for ActiveRecord 3.1 statement pool, to avoid `ORA-01000` maximum open cursors exceeded (default `statement_limit` is 250 and can be changed in `database.yml`) [#100]
  * Added error handling for `rename_table` method in migrations [#137]
* Bug fixes:
  * Store primary key as `nil` in cache at first time for table without primary key [#84]
  * Fixed inserting records with decimal type columns (`ORA-01722` invalid number exceptions) [#130]
  * Check virtual columns only in models that are using `oracle-enhanced` adapter, to avoid problems when using multiple database adapters [#85]
  * Don't drop the user in rake `db:create` and `db:drop` tasks [#103]
  * Don't add `db:create` and `db:drop` when ActiveRecord is not used as the primary datastore [#128]
  * Quote column names in LOB statements to avoid `ORA-00936` errors [#91]
  * Don't add the `RETURNING` clause if using `composite_primary_keys` gem [#132]
  * Added `join_to_update` method that is necessary for ActiveRecord 3.1 to ensure that correct UPDATE statement is generated using `WHERE ... IN` subquery with offset condition

### 1.4.0 / 2011-08-09

* Enhancements:
  * Support for Rails 3.1
  * Bind parameter support for exec_insert, exec_update and exec_delete (in ActiveRecord 3.1)
  * Purge recyclebin on rake db:test:purge
  * Support transactional context index
  * Require ojdbc6.jar (on Java 6) or ojdbc5.jar (on Java 5) JDBC drivers
  * Support for RAW data type
  * rake db:create and db:drop tasks
  * Support virtual columns (in Oracle 11g) in schema dump
  * It is possible to specify default tablespaces for tables, indexes, CLOBs and BLOBs
  * rename_index migrations method
  * Search for JDBC driver in ./lib directory of Rails application
* Bug fixes:
  * Fixed context index dump when definition is larger than 4000 bytes
  * Fixed schema dump not to conflict with other database adapters that are used in the same application
  * Allow $ in table name prefix or suffix

### 1.3.2 / 2011-01-05

* Enhancements:
  * If no :host or :port is provided then connect with :database name (do not default :host to localhost)
  * Database connection pool support for JRuby on Tomcat and JBoss application servers
  * NLS connection parameters support via environment variables or database.yml
  * Support for Arel 2.0 and latest Rails master branch
  * Support for Rails 3.1 prepared statements (implemented in not yet released Rails master branch version)
  * Eager loading of included association with more than 1000 records (implemented in not yet released Rails master branch version)
* Bug fixes:
  * Foreign keys are added after table definitions in schema dump to ensure correct order of schema statements
  * Quote NCHAR and NVARCHAR2 type values with N'...'
  * Numeric username and/or password in database.yml will be automatically converted to string

### 1.3.1 / 2010-09-09

* Enhancements:
  * Tested with Rails 3.0.0 release
  * Lexer options for context index creation
  * Added Bundler for running adapter specs, added RUNNING_TESTS.rdoc with description how to run specs
  * Connection to database using :host, :port and :database options
  * Improved loading of adapter in Rails 3 using railtie
* Bug fixes:
  * Fix for custom context index procedure when indexing records with null values
  * Quote table and column names in write_lobs callback
  * Fix for incorrect column SQL types when two models use the same table and AR query cache is enabled
  * Fixes for schema and scructure dump tasks
  * Fix for handling of zero-length strings in BLOB and CLOB columns
  * removed String.mb_chars upcase and downcase methods for Ruby 1.9 as Rails 3.0.0 already includes Unicode aware upcase and downcase methods for Ruby 1.9
  * Fixes for latest ActiveRecord unit tests

### 1.3.0 / 2010-06-21

* Enhancements:
  * Rails 3.0.0.beta4 and Rails 2.3.x compatible
  * When used with Rails 3 then works together with Oracle SQL compiler included in Arel gem (http://github.com/rails/arel)
  * Rails 3: Better support for limit and offset (when possible adds just ROWNUM condition in WHERE clause without using subqueries)
  * Table and column names are always quoted and in uppercase to avoid the need for checking Oracle reserved words
  * Full text search index creation (add_context_index and remove_context_index methods in migrations and #contains method in ActiveRecord models)
  * add_index and remove_index give just warnings on wrong index names (new expected behavior in Rails 2.3.8 and 3.0.0)
  * :tablespace and :options options for create_table and add_index
* Workarounds:
  * Rails 3: set ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.cache_columns = true in initializer file for all environments
    (to avoid too many data dictionary queries from Arel)
  * Rails 2.3: patch several ActiveRecord methods to work correctly with quoted table names in uppercase (see oracle_enhanced_activerecord_patches.rb).
    These patches are already included in Rails 3.0.0.beta4.
* Bug fixes:
  * Fixes for schema purge (drop correctly materialized views)
  * Fixes for schema dump and structure dump (use correct statement separator)
  * Only use Oracle specific schema dump for Oracle connections

### 1.2.4 / 2010-02-23

* Enhancements:
  * rake db:test:purge will drop all schema objects from test schema (including views, synonyms, packages, functions, procedures) -
    they should be always reloaded before tests run if necessary
  * added views, synonyms, packages, functions, procedures, indexes, triggers, types, primary, unique and foreign key constraints to structure dump
  * added :temporary option for create_table to create temporary tables
  * added :tablespace option for add_index
  * support function based indexes in schema dump
  * support JNDI database connections in JRuby
  * check ruby-oci8 minimum version 2.0.3
  * added savepoints support (nested ActiveRecord transactions)
* Bug fixes:
  * typecast returned BigDecimal integer values to Fixnum or Bignum
    (to avoid issues with _before_type_cast values for id attributes because _before_type_cast is used in form helpers)
  * clear table columns cache after columns definition change in migrations

### 1.2.3 / 2009-12-09

* Enhancements
  * support fractional seconds in TIMESTAMP values
  * support for ActiveRecord 2.3.5
  * use ENV['TZ'] to set database session time zone
    (as a result DATE and TIMESTAMP values are retrieved with correct time zone)
  * added cache_columns adapter option
  * added current_user adapter method
  * added set_integer_columns and set_string_columns ActiveRecord model class methods
* Bug fixes:
  * do not raise exception if ENV['PATH'] is nil
  * do not add change_table behavior for ActiveRecord 2.0 (to avoid exception during loading)
  * move foreign key definitions after definition of all tables in schema.rb
    (to avoid definition of foreign keys before all tables are created)
  * changed timestamp format mask to use ':' before fractional seconds
    (workaround to avoid table detection in tables_in_string method in ActiveRecord associations.rb file)
  * fixed custom create/update/delete methods with ActiveRecord 2.3+ and timestamps
  * do not call oracle_enhanced specific schema dump methods when using other database adapters

### 1.2.2 / 2009-09-28

* Enhancements
  * improved RDoc documentation of public methods
  * structure dump optionally (database.yml environment has db_stored_code: yes) extracts
    packages, procedures, functions, views, triggers and synonyms
  * automatically generated too long index names are shortened down to 30 characters
  * create tables with primary key triggers
  * use 'set_sequence_name :autogenerated' for inserting into legacy tables with trigger populated primary keys
  * access to tables over database link (need to define local synonym to remote table and use local synonym in set_table_name)
  * [JRuby] support JDBC connection using TNS_ADMIN environment variable and TNS database alias
  * changed cursor_sharing option default from 'similar' to 'force'
  * optional dbms_output logging to ActiveRecord log file (requires ruby-plsql gem)
  * use add_foreign_key and remove_foreign_key to define foreign key constraints
    (the same syntax as in http://github.com/matthuhiggins/foreigner and similar
    to http://github.com/eyestreet/active_record_oracle_extensions)
  * raise RecordNotUnique and InvalidForeignKey exceptions if caused by corresponding ORA errors
    (these new exceptions are supported just by current ActiveRecord master branch)
  * implemented disable_referential_integrity
    (enables safe loading of fixtures in schema with foreign key constraints)
  * use add_synonym and remove_synonym to define database synonyms
  * add_foreign_key and add_synonym are also exported to schema.rb
* Bug fixes:
  * [JRuby] do not raise LoadError if ojdbc14.jar cannot be required (rely on application server to add it to class path)
  * [JRuby] 'execute' can be used to create triggers with :NEW reference
  * support create_table without a block
  * support create_table with Symbol table name
  * use ActiveRecord functionality to do time zone conversion
  * rake tasks such as db:test:clone are redefined only if oracle_enhanced is current adapter in use
  * VARCHAR2 and CHAR column sizes are defined in characters and not in bytes (expected behavior from ActiveRecord)
  * set_date_columns, set_datetime_columns, ignore_table_columns will work after reestablishing connection
  * ignore :limit option for :text and :binary columns in migrations
  * patches for ActiveRecord schema dumper to remove table prefixes and suffixes from schema.rb

### 1.2.1 / 2009-06-07

* Enhancements
  * caching of table indexes query which makes schema dump much faster
* Bug fixes:
  * return Date (and not DateTime) values for :date column value before year 1970
  * fixed after_create/update/destroy callbacks with plsql custom methods
  * fixed creation of large integers in JRuby
  * Made test tasks respect RAILS_ENV
  * fixed support for composite primary keys for tables with LOBs

### 1.2.0 / 2009-03-22

* Enhancements
  * support for JRuby and JDBC
  * support for Ruby 1.9.1 and ruby-oci8 2.0
  * support for Rails 2.3
  * quoting of Oracle reserved words in table names and column names
  * emulation of OracleAdapter (for ActiveRecord unit tests)
* Bug fixes:
  * several bug fixes that were identified during running of ActiveRecord unit tests

### 1.1.9 / 2009-01-02

* Enhancements
  * Added support for table and column comments in migrations
  * Added support for specifying sequence start values
  * Added :privilege option (e.g. :SYSDBA) to ActiveRecord::Base.establish_connection
* Bug fixes:
  * Do not mark empty decimals, strings and texts (stored as NULL in database) as changed when reassigning them (starting from Rails 2.1)
  * Create booleans as VARCHAR2(1) columns if emulate_booleans_from_strings is true

### 1.1.8 / 2008-10-10

* Bug fixes:
  * Fixed storing of serialized LOB columns
  * Prevent from SQL injection in :limit and :offset
  * Order by LOB columns (by replacing column with function which returns first 100 characters of LOB)
  * Sequence creation for tables with non-default primary key in create_table block
  * Do count distinct workaround only when composite_primary_keys gem is used
    (otherwise count distinct did not work with ActiveRecord 2.1.1)
  * Fixed rake db:test:clone_structure task
    (see http://rsim.lighthouseapp.com/projects/11468/tickets/11-rake-dbtestclone_structure-fails-in-117)
  * Fixed bug when ActiveRecord::Base.allow_concurrency = true
    (see http://dev.rubyonrails.org/ticket/11134)

### 1.1.7 / 2008-08-20

* Bug fixes:
  * Fixed that adapter works without ruby-plsql gem (in this case just custom create/update/delete methods are not available)

### 1.1.6 / 2008-08-19

* Enhancements:
  * Added support for set_date_columns and set_datetime_columns
  * Added support for set_boolean_columns
  * Added support for schema prefix in set_table_name (removed table name quoting)
  * Added support for NVARCHAR2 column type
* Bug fixes:
  * Do not call write_lobs callback when custom create or update methods are defined
    
### 1.1.5 / 2008-07-27

* Bug fixes:
  * Fixed that write_lobs callback works with partial_updates enabled (added additional record lock before writing BLOB data to database)
* Enhancements:
  * Changed SQL SELECT in indexes method so that it will execute faster on some large data dictionaries
  * Support for other date and time formats when assigning string to :date or :datetime column

### 1.1.4 / 2008-07-14

* Enhancements:
  * Date/Time quoting changes to support composite_primary_keys
  * Added additional methods that are used by composite_primary_keys

### 1.1.3 / 2008-07-10

* Enhancements:
  * Added support for custom create, update and delete methods when working with legacy databases where
    PL/SQL API should be used for create, update and delete operations

### 1.1.2 / 2008-07-08

* Bug fixes:
  * Fixed after_save callback addition for session store in ActiveRecord version 2.0.2
  * Changed date column name recognition - now should match regex /(^|_)date(_|$)/i
    (previously "updated_at" was recognized as :date column and not as :datetime)

### 1.1.1 / 2008-06-28

* Enhancements:
  * Added ignore_table_columns option
  * Added support for TIMESTAMP columns (without fractional seconds)
  * NLS_DATE_FORMAT and NLS_TIMESTAMP_FORMAT independent DATE and TIMESTAMP columns support
* Bug fixes:
  * Checks if CGI::Session::ActiveRecordStore::Session does not have enhanced_write_lobs callback before adding it
    (Rails 2.0 does not add this callback, Rails 2.1 does)

### 1.1.0 / 2008-05-05

* Forked from original activerecord-oracle-adapter-1.0.0.9216
* Renamed oracle adapter to oracle_enhanced adapter
  * Added "enhanced" to method and class definitions so that oracle_enhanced and original oracle adapter
    could be used simultaniously
  * Added Rails rake tasks as a copy from original oracle tasks
* Enhancements:
  * Improved perfomance of schema dump methods when used on large data dictionaries
  * Added LOB writing callback for sessions stored in database
  * Added emulate_dates_by_column_name option
  * Added emulate_integers_by_column_name option
  * Added emulate_booleans_from_strings option
