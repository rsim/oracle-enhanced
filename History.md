## 5.2.1 / 2018-04-15

* Changes and bug fixes
  * Memoize if the table needs to prefetch primary key[#1673 #1699 #1700]

## 5.2.0 / 2018-04-10

* Major changes and fixes
  * Support Rails 5.2.0

* Documentation changes
  * Add README and UPGRADE sections for Rails 5.2 [#1637 #1638]
  * Update bug templates for Rails 5.2 [#1663]

* Changes in specs
  * Suppress expected exceptions by `report_on_exception` = `false` [#1655 #1656]

* Changes for CI and builds
  * CI with JRuby 9.1.16.0 [#1659]
  * CI with Ruby 2.5.1 [#1683 #1684]
  * CI against Ruby 2.4.4 [#1686 #1687]
  * Use ruby 2.3.7 and 2.2.10 for CI at release52 branch [#1688]
  * Oracle enhanced adapter 5.2 needs Rails `5-2-stable` branch [#1654]

## 5.2.0.rc1 / 2018-01-31

* Changes and bug fixes

  * Support Rails 5.2.0.rc1
  * Do not register `VARCHAR2(1)` sql type as `Type:Boolean` [#1621 #1623]
  * Support `insert_fixtures_set` [#1633]
  * Deprecated `insert_fixtures` [#1634]
  * Refactor index options dumping [#1602]
  * Skip failed spec explained at #1599 [#1599 #1604]
  * CI with Ruby 2.5.0 [#1618]
  * CI against JRuby 9.1.15.0 [#1605]
  * Enable `Layout/SpaceBeforeComma` [#1606]
  * Enable `Layout/LeadingCommentSpace` cop [#1607]
  * Enable autocorrect for `Lint/EndAlignment` cop [#1629]
  * Remove `--force` option for installing bundler [#1616]

## 5.2.0.beta1 / 2017-11-27

* Major changes and fixes

  * Support Rails 5.2.0.beta1
  * Oracle enhanced adapter version follows Rails versioning [#1488]
  * Handle `TIMESTAMP WITH TIMEZONE` separately from `TIMEZONE` [#1267]
  * Support `timestamptz` and `timestampltz` for migrations #1285
  * `supports_json?` returns false [#1562]
  * Add synonyms in `data_sources` [#1380, #1567]
  * Add sequence with settings to structure dump [#1354]
  * Support for NCLOB datatype [#1428, #1440]
  * Use conventional fixture load [#1366]
  * Address `ORA-00905: missing keyword: EXPLAIN PLAN FOR` [#1384]
  * Use new method name for active record dirty checks [#1406]
  * check for schema name when validating table name [#1408, #1410]
  * Prefer to place a table options before `force: :cascade` [#1457]
  * Enable TCP keepalive for OCI connections [#1489]
  * Do not expose `all_schema_indexes` [#1495]
  * Using bind variables for dictionary access [#1498]
  * Use bind variables for `table_comment` `column_comment` `foreign_keys` [#1502]
  * Respect database instance `cursor_sharing` value `exact` by default [#1503, #1556]
  * Address `CommentTest#test_change_table_comment_to_nil` failure [#1504]
  * Address explain with binds errors [#908, #1386, #1538]
  * Address `MigrationTest#test_create_table_with_query_from_relation` error [#1543]
  * Follow the new interface of AR::ConnectionAdapters::IndexDefinition#initialize [#1295]
  * Remove `lengths`, `where`, `using` from `IndexDefinition` [#1529]
  * Arity change in insert method [#1382]
  * Restore the ability that SQL with binds for `insert` [#1424]
  * Restore `to_sql` to return only SQL [#1423]
  * Signature fix for `select_one` `select_value` `select_values` [#1475]
  * `columns` second argument does not exist in Abstract adapter [#1519]
  * Arel::Nodes::BindParam#initialize introduced [#1383]
  * Log the purpose of sql in `disable_referential_integrity` [#1550]
  * Change log format of "Primary Key Trigger" to one line [#1551]
  * Log multi lines SQL statements into one line [#1553]
  * Log multi lines SQL statements into one line at `structure_dump.rb` [#1555]
  * [ci skip] `open_cursors` value should be larger than `:statement_limit` [#1573]
  * [skip ci] Add `schema` option in the comment [#1574]
  * [skip ci] `emulate_booleans_from_strings` behavior changes [#1576]
  * Restore calling `OCIConnection#bind_returning_param` [#1581]
  * Add these errors to be recognized as `ActiveRecord::StatementInvalid` [#1584]
  * Add `ORA-02289` to be recognized as `ActiveRecord::StatementInvalid` [#1586]
  * Address `BasicsTest#test_clear_cache!` failure [#1587]
  * Use Bundler 1.15 to workaround bundler/bundler#6072 [#1590]
  * Translate `ORA-00060` into `ActiveRecord::Deadlocked` error [#1591]
  * Add `ORA-02449` to be recognized as `ActiveRecord::StatementInvalid` [#1593, #1596]
  * Support `discard!` method [#1598]

* Deprecation or removing deprecated code

  * Remove `OracleEnhancedAdapter.cache_columns` [#1490, #1492]
  * Deprecate `supports_statement_cache?` [#1321]
  * Remove `compress_lines` [#1327]
  * Remove `OracleEnhanced::SchemaDumper::TableInspect` [#1400]
  * Remove `remove_prefix_and_suffix` and specs from Oracle enhanced adapter [#1420]
  * Remove unused returning value `stream` [#1438]
  * Remove `OracleEnhancedAdapter.emulate_dates` [#1448]
  * Remove `emulate_dates` and `emulate_dates_by_column_name` [#1450]
  * Remove `emulate_integers_by_column_name` [#1451]
  * Remove `@@do_not_prefetch_primary_key` class variable [#1496]
  * Remove `string_to_date` which has been removed from Rails 4.2 [#1509]
  * Remove `string_to_time` which has been removed from Rails 4.2 [#1510]
  * Remove `guess_date_or_time` which has not been called [#1511]
  * Remove unused `object_type?` and `object_type` ivar [#1512]
  * Remove non-existent `:nchar` from `attr_reader` [#1513]
  * Remove `ActiveRecord::ConnectionAdapter::OracleEnhanced::Column#lob?` [#1522]
  * Remove `OracleEnhanced::Column#returning_id?` [#1523]
  * Remove `attr_reader :table_name` [#1524]
  * Remove `combine_bind_parameters` [#1527]
  * Remove `OracleEnhancedAdapter.default_tablespaces[native_database_types[type][:name]]` [#1544]
  * Remove unused `require "digest/sha1"` [#1545]
  * Remove deprecations for 5.2 [#1548]
  * Remove `OracleEnhanced::Connection#select_values` [#1558]
  * Remove `@connection` from `@connection.oracle_downcase` and `@connection.select_value` [#1559]
  * Rename `OracleEnhanced::Connection#select_value` to `_select_value` [#1563]
  * Rename `OracleEnhanced::Connection#oracle_downcase` to `_oracle_downcase` [#1565]
  * Remove `OCIConnection#typecast_result_value` handling `OraNumber` [#1578]
  * [skip ci] Changing `NLS_DATE_FORMAT` and `NLS_TIMESTAMP_FORMAT` is not supported [#1575]
  * [skip ci] Remove ruby versions in the comment [#1577]
  * Remove `OCIConnection#returning_clause` and `JDBCConnection#returning_clause` [#1579]
  * Remove `OCIConnection#exec_with_returning` and `JDBCConnection#exec_with_returning` [#1580]
  * Update `JDBCConnection#bind_param` case condition [#1583]

* Refactoring

  * Refactor `SchemaDumper` to make it possible to adapter specific customization [#1430]
  * Rename `SchemaDumper#indexes` to `SchemaDumper#_indexes` [#1399]
  * Use ActiveRecord::Type::Json [#1352]
  * Introduce module `DatabaseLimits` [#1322]
  * Move `oracle_downcase` to `Quoting` module [#1328]
  * Make `type_map` to private because it is only used in the connection adapter [#1381]
  * Remove `add_runtime_dependency` with arel [#1385]
  * Move methods for synonyms out of `SchemaStatementsExt` [#1387]
  * Remove incorrect prepend to `ActiveRecord::ColumnDumper` [#1394]
  * Handle `ActiveRecord::SchemaDumper` by `adapter_name` [#1395] 
  * Rewrite `remove_prefix_and_suffix` to be similar with super #1401
  * `remove_prefix_and_suffix` handles dollar sign by `Regexp#escape` [#1402]
  * `prepare_column_options` is now private [#1429]
  * Introduce `OracleEnhanced::SchemaStatements#table_options` [#1439]
  * Extract `ActiveRecord::ConnectionAdapters::OracleEnhanced::Column` [#1445]
  * Extract `ActiveRecord::ConnectionAdapters::OracleEnhanced::DbmsOutput` [#1446]
  * Introduce `SchemaDumpingHelper#dump_table_schema` [#1455]
  * Rename `OracleEnhancedConnection` to `OracleEnhanced::Connection` [#1477]
  * Introduce `ActiveRecord::ConnectionAdapters::OracleEnhanced::TypeMetadata` [#1515]
  * Change `schema_creation` to private [#1517]
  * Change `create_table_definition` and `fetch_type_metadata` to private [#1518]
  * Refactor `columns` [#1521]
  * Let `ActiveRecord::ConnectionAdapters::OracleEnhanced::TypeMetadata` handle `virtual` type [#1526]
  * Clean up `column_definitions` method [#1528]
  * Remove unnecessary `ActiveRecord::ConnectionAdapters` [#1530]
  * Rename `OracleEnhancedStructureDump` to `OracleEnhanced::StructureDump` [#1531]
  * Move up require for types [#1533]
  * These methods are private in `AbstractAdapter` or `PostgreSQLAdapter` [#1534]
  * `ActiveRecord::ConnectionAdapters::AbstractAdapter#log` is a `private` [#1535]
  * Move `self.default_sequence_start_value` method [#1536]
  * Rename `ActiveRecord::OracleEnhanced::Type` to `ActiveRecord::Type::OracleEnhanced` [#1541]
  * Move `write_lobs` under `OracleEnhanced::DatabaseStatements` module [#1546]
  * Introduce `OracleEnhanced::Lob` not to modify `ActiveRecord::Base` directly [#1547]
  * Use `ActiveSupport.on_load` to hook into `ActiveRecord::Base` [#1568]
  * Call `virtual_columns_for` when `supports_virtual_columns?` returns true [#1554]
  * Move `tables` and related methods into `OracleEnhanced::SchemaStatements` [#1557]
  * Avoid using `OracleEnhanced::Connection#select_value` [#1560]
  * Make `OracleEnhanced::Connection#describe` private [#1566]

* Changes in specs

  * Always generate `debug.log` for unit tests [#1476]
  * Use Rails migration for creating table at "using offset and limit" [#1276]
  * Use Rails migration for creating table at `valid_type?` [#1277]
  * Clean up before(:each) and after(:each) at "rename tables and sequences" [#1278]
  * Use Rails migration for creating table at `BINARY_FLOAT columns" specs [#1280]
  * Use Rails migration for creating table at "handling of BLOB columns" [#1282]
  * Use Rails migration for creating table at "handling of CLOB columns" [#1283]
  * Use Rails migration for creating table at "assign string to :date and :datetime columns" [#1284]
  * Use Rails migration for creating table at "table columns" [#1287]
  * Use Rails migration for creating table at procedure specs [#1288]
  * Use Rails migration for creating table at database tasks specs [#1290]
  * Suppress `warning: assigned but unused variable - poolable_connection_factory` [#1292]
  * Suppress `warning: assigned but unused variable - post` [#1293]
  * Move spec files under `oracle_enhanced` directory [#1441]
  * Move spec files under `emulation` directory [#1442]
  * Move schema_dumper_spec under `oracle_enhanced` directory [#1443]
  * Rename spec/active_record/connection_adapters/oracle_enhanced_dirty_spec.rb [#1447]
  * Remove `set_boolean_columns` from `oracle_enhanced_data_types_spec.rb` [#1452]
  * Remove `set_string_columns` from `oracle_enhanced_data_types_spec.rb` [#1454]
  * Use `drop_table` if_exists: true` to avoid rescue nil [#1456]
  * Extract JSON data type specs [#1459]
  * Extract NationalCharacterString data type specs [#1460]
  * Extract RAW data type specs [#1461]
  * Extract TEXT data type specs [#1462]
  * Extract INTEGER data type specs [#1463]
  * Remove redundant `type` from spec files [#1464]
  * Extract boolean data type specs [#1465]
  * Extract NationalCharacterText data type specs [#1466]
  * Extract specs for `OracleEnhanced::Quoting` [#1469]
  * Extract TIMPSTAMP, TIMESTAMPTZ and TIMESTAMPLTZ specs [#1480]
  * Extract FLOAT type specs [#1482]
  * Use `SchemaDumpingHelper#dump_table_schema` at `context_index_spec` [#1491]
  * Remove unused `fk_name` [#1514]
  * Show correct bind value information in debug.log [#1537]
  * rubocop 0.48.1 [#1281]

* Changes for CI and builds

  * Use `rubocop-0-51` channel on Code Climate [#1589]
  * Use `rubocop-0-50` channel on Code Climate [#1539]
  * Use `rubocop-0-49` channel to run rubocop 0.49 [#1478]
  * Bump ruby versions to 2.4.2, 2.3.5 and 2.2.8 at Travis [#1484]
  * CI against JRuby 9.1.14.0 [#1592]
  * CI against JRuby 9.1.13.0 [#1471]
  * set `open_cursor` value to `1200` [#1431]
  * Use bundler 1.16.0.preX and update rubygems to the latest [#1532]
  * [ci skip] Create an issue template [#1317]
  * [ci skip] Add Oracle enhanced adapter version to the issue template [#1319]
  * [ci skip] Remove `self.emulate_integers_by_column_name = true` [#1494]
  * Remove leftover comments [ci skip] [#1520]
  * Move issue template to github sub directory [skip ci] [#1320]
  * Replace :github source with https [#1499]
  * Simplify `git_source` in Gemfile [#1500]
  * Enable and apply `Style/Semicolon` [#1570]
  * Enable and apply Style/RedundantReturn [#1571]
  * Enable `Style/DefWithParentheses` rubocop rule [#1597]
  * bundler 1.16.0 is out, no more --pre [#1572]

## 1.8.2 / 2017-08-24

* Changes and bug fixes
  * Fix cursor leak when using activerecord-import gem [#1409, #1433]
  * Mention new statement_limit default [#1364, #1365]
  * Add upgrade section for `:statement_limit` value at Rails 5.1 [#1362, #1363]
  * Set `disk_asynch_io` to `false` [#1413, #1414]
  * Update README.md [#1367 #1368]
  * CI against JRuby 9.1.12.0 [#1359, #1360]
  * Bump ruby versions [#1346]
  * rubocop namespace changes from `Style` to `Layout` [#1347, #1351]

* Known issues
  * No changes since 1.8.0.rc3

## 1.8.1 / 2017-05-11

* Changes and bug fixes
  * Address `undefined method `tablespace' for #<ActiveRecord::ConnectionAdapters::IndexDefinition [#1332, #1334, #1336]
  * Rails 5.1.0.rcX is not supported anymore [#1311]
  * Use Ubuntu 12.04 at Travis [#1324]

## 1.8.0 / 2017-04-27

* Major enhancements
  * Support Rails 5.1.0
  * Add JSON attribute support [#1240]
  * Update `database.yml` when `rails new <new_app> -d oracle` specified [rails/rails#28257]

* Changes and bug fixes
  * No changes since 1.8.0.rc3

## 1.8.0.rc3 / 2017-04-24

* Changes and bug fixes
  * Include VERSION file in gem [#1302, #1303]

## 1.8.0.rc2 / 2017-04-19

* Changes and bug fixes
  * Fix `select_all` with legacy `binds` [#1246,#1248,#1250]
  * Fix the `BINARY_FLOAT` column type returns nil in JRuby [#1244, #1254, #1255]
  * Handle `TIMESTAMP WITH TIMEZONE` separately from `TIMEZONE` [#1206, #1267, #1268]
  * Changing `NLS_DATE_FORMAT` and `NLS_TIMESTAMP_FORMAT` is not supported [#1267, #1268]
  * Let abstract adapter type cast Date, DateTime and Time for JRuby [#1272, #1273]
  * Collapse a file specification in gemspec [#1296, #1297]
  * Do not write VERSION directly with gemspec [#1298, #1299]
  * Omit specification of release date in gemspec [#1298, #1299]
  * Add missing `timestamptz.rb` to gemspec at release18 branch [#1286]
  * Remove specs for unsupported behaviour which causes `ORA-01861` [#1267, #1269, #1271]
  * Address `OCIException: OCI8 was already closed` at specs for JSON [#1265, #1266]
  * Bump Ruby version to 2.2.7 [#1261]

## 1.8.0.rc1 / 2017-03-20

* Major enhancements
  * Support Rails 5.1.0.rc1
  * Add JSON attribute support #1240
  * Update `database.yml` when `rails new <new_app> -d oracle` specified [rails/rails#28257]

* Changes and bug fixes
  * Eliminate a redundant empty lines in schema.rb generated by SchemaDumper [#1232]
  * Align the columns of db/structure.sql [#1242]
  * Use Abstract StatementPool (new `statement_limit` default is 1000 was 250) [#1228]
  * Decouple Composite Primary Key code [#1224, #1225]
  * Push `valid_type?` up to abstract adapter [#1208]
  * Oracle12 visitor is also available for 12.2 [#1217]
  * Oracle Database 12c Release 2 bundles new ojdbc8.jar [#1218]
  * Deprecate `supports_migrations?` on connection adapters [#1209]
  * Use `ActiveRecord::SchemaMigration.table_name` [#1221]
  * No need to check if `changed?` defined [#1226]
  * No need to initialize `@quoted_column_names` and `@quoted_table_names` [#1227]
  * Hard code `empty_blob()` or `empty_clob()` based on types [#1229]
  * ruby-plsql 0.6.0 or higher version is required [#1216]
  * No need to specify `rack` in Gemfile [#1230]
  * Bundle from more secure source [#1243]
  * Add Travis CI build status [#1231]
  * Bump JRuby to 9.1.8.0 [#1222]
  * Remove a duplicate spec testing `Model.distinct.count` [#1235]
  * Suppress unused and not initialized warnings [#1215]
  * Suppress `WARNING: Using the `raise_error` matcher without providing a specific error` [#1219]
  * Suppress `WARNING: Using `expect { }.not_to raise_error(...)` risks false positives` [#1220]

## 1.8.0.beta1 / 2017-02-27

* Major enhancements
  * Support Rails 5.1.0.beta1
  * Fallback :bigint to :integer for primary keys [#1077]
  * Drop Java SE 6 or older version of Java SE support [#1126]
  * Drop JRuby 9.0.x support for Rails 5.1 [#1147]
  * Refactor ColumnDumper to support consistent Virtual column with Rails [#1185]
  * Schema dumper supports `t.index` in `create_table` [#1187]
  * `table_exists?` only checks tables, does not check views [#1179, #1191]
  * `data_sources` returns tables and views [#1192]
  * `Model.table_comment` syntax is not supported anymore [#1199]
  * Remove Oracle enhanced adapter own foreign key implementations [#977]

* Changes and bug fixes
  * Rails 5.1.0.beta1 is out [#1204]
  * Composite foreign keys are not supported [#1188]
  * Introduce `supports_virtual_columns?` [#1184]
  * Made it able to change column with adding comment [#1156, #1164]
  * Omit table comment option of schema.rb if it is blank [#1159]
  * Fix to return nil if column comment is blank at table creation [#1158]
  * `bind_param` arity change, not to take column [#1203]
  * ActiveRecord `structure_dump` and `structure_load` signature changes [#1125]
  * Quoting booleans should return a frozen string [#956]
  * Pass `type_casted_binds` to log subscriber [#957]
  * `supports_datetime_with_precision?` always returns `true` [#964]
  * Handle ORA-00942 and ORA-00955 as `ActiveRecord::StatementInvalid` [#1093]
  * Raise `ActiveRecord::StatementInvalid` at `rename_index` when old index does not exist [#1195]
  * Handle `ORA-01418: specified index does not exist` as `ActiveRecord::StatementInvalid` [#1195]
  * Raise ActiveRecord::NotNullViolation when OCIError: ORA-01400 [#1174]
  * Rails 5.1 : insert into `returning_id` not working since rails/rails#26002 [#988, #1088]
  * Make `exec_{insert,update}` signatures consistent [#966]
  * Introduce OracleEnhanced `ColumnMethods` module and `AlterTable` `Table` classes [#1081]
  * `empty_insert_statement_value` is not implemented [#1180]
  * Switch to keyword args for `type_to_sql` [#1167, #1168]
  * Replace `all_timestamp_attributes` with `all_timestamp_attributes_in_model` [#1129]
  * `current_database` returns the expected database name [#1135]
  * Use `supports_foreign_keys_in_create?` [#1143]
  * Address `add_column` gets `ArgumentError: wrong number of arguments` [#1157, #1170]
  * Address `change_column` `ArgumentError: wrong number of arguments` [#1171, #1172]
  * SchemaDumper should not dump views as tables [#1192]
  * Use Abstract `select_rows(arel, name = nil, binds = [])` [#1132]
  * Address `OCIError: ORA-01756: quoted string not properly terminated:` [#1102]
  * Use `table_exists?` and `tables` [#1170, #1178]
  * Move `ActiveModel::Type::Text` to `ActiveRecord::Type::Text` [#1082]
  * Support schema option for views [#1190]
  * Quote table and trigger names containing sinqle quote character [#1192]
  * Restore :raw type migration support [#1176]
  * Refactor Boolean type by removing duplicate code [#1047]
  * Remove deprecated methods to get and set columns [#958]
  * Remove `is_?` deprecated methods [#959]
  * Remove `quote_date_with_to_date` and `quote_timestamp_with_to_timestamp` #960
  * Remove unnecessary comments in Type [#961]
  * Remove options[:default] for virtual columns [#962]
  * Remove `self.emulate_dates` and `self.emulate_dates_by_column_name` [#963]
  * Delete `self.boolean_to_string` [#967]
  * Delete Oracle enhanced its own `join_to_update` [#968]
  * Remove `self.ignore_table_columns` [#969]
  * Remove unused `self.virtual_columns` [#970]
  * Remove `dump_schema_information` and `initialize_schema_migrations_table` [#972]
  * Remove `fallback_string_to_date`, `fallback_string_to_time` [#974, #975, #1112]
  * Remove `dependent` option from `add_foreign_key` [#976]
  * Remove specs testing Rails `self.ignored_columns` features [#987]
  * Remove `add_foreign_key` specs with `table_name_prefix` and `table_name_suffix` [#990]
  * Remove `type_cast` method just calling super [#1201]
  * Remove `ids_in_list_limit` alias [#1202]
  * Remove unused comments from data types spec [#1079]
  * Remove deprecated `table_exists?` and `tables` [#1100, #1178]
  * Remove deprecated `name` argument from `#tables` [#1189]
  * Prefer `SYS_CONTEXT` function than `v$nls_parameters` view [#1107]
  * `initialize_schema_migrations_table` method has been removed [#1144]
  * `index_name_exists?` at schema statements spec is not necessary [#1197]
  * Remove comments for `data_source_exists?` [#1200]
  * Address DEPRECATION WARNING: Passing a column to `quote` has been deprecated. [#978]
  * Deprecate `supports_primary_key?` [#1177]
  * Deprecate passing `default` to `index_name_exists?` [#1175]
  * Suppress `add_index_options` method `DEPRECATION WARNING:` [#1193]
  * Suppress `remove_index` method deprecation warning [#1194]
  * Suppress DEPRECATION WARNING at `rename_index` [#1195]
  * Suppress `oracle_enhanced_adapter.rb:591: warning: assigned but unused` [#1198]
  * Use rails rubocop setting [#1111]
  * Rubocop addresses `Extra empty line detected at class body beginning.` [#1078]
  * Address `Lint/EndAlignment` offences by changing code ifself [#1113]
  * rubocop `AlignWith` has been renamed to `EnforcedStyleAlignWith` [#1142]
  * Add `Style/EmptyLinesAroundMethodBody` [#1173]
  * Address git warnings: [#1000]
  * Update `required_rubygems_version` just following rails.gemspec [#1110]
  * Use the latest ruby-plsql while developing alpha version [#1114]
  * Use the latest arel master while developing alpha version [#1115]
  * Bump Arel to 8.0 [#1120, #1121, #1124]
  * Use released Arel 8 [#1205]
  * Remove duplicate license information [#965] 
  * Clean up comments and un-commented specs for table comment feature [#971]
  * Use Rails migration `create_table` to create table and sequence [#991]
  * Removed a invalid spec about TIMESTAMP column [#1020]
  * Remove specs which set `attribute :hire_date, :date` [#1024]
  * Remove version specification for rspec [#1055]
  * Suppress `create_table(:test_employees, {:force=>true})` message [#1080]
  * Perform `drop_table :test_employees` [#1087]
  * Address rspec deprecation warning [#1089]
  * Suppress rspec warning [#1101]
  * Suppress `Dropped database 'ORCL'` messages while running rspec [#1103]
  * Address rspec warnings by checking with `raise_errors_for_deprecations!` [#1104]
  * `clear_cache!` always exists at least since Rails 4.0 [#1106]
  * Use SimpleCov [#1108]
  * Enable RSpec `--warnings` option [#1116]
  * Remove entry for rcov since it already migrated to simplecov [#1118]
  * Add spec for #1149 `TypeError: can't cast Java::JavaSql::Timestamp` [#1152]
  * Remove a duplicated specs [#1163]
  * Specify `--require spec_helper` in .rspec [#1186]
  * Add 'pry' and 'pry-nav' for JRuby debug [#973]
  * Remove ruby-debug [#1196]
  * Use Ubuntu Trusty at travis [#1095]
  * Address travis.yml has multilpe language entries [#1109]
  * Use docker-oracle-xe-11g for Travis CI [#1117]
  * Modify `JRUBY_OPTS` for Travis CI [#1119]
  * Add ruby-head and jruby-head to .travis.yml [#1127]
  * Use JRuby 9.1.7.0 [#1138]
  * Add JRuby 9.0.4.0 and allow JRuby 9.0.5.0 failures [#1146]
  * Tiny fix for .travis.yml after migrating to docker-oracle-xe-11g [#1183]
  * Templates updated to use Rails master branch for Rails 5.1 [#1133]
  * Update running tests to include rails-dev-box [#1140]

* Known issues
  * Legacy primary key support testing [#1207]
  * PrimaryKeyIntegerNilDefaultTest failures [#1162]
  * Skip `explain should explain query with bind` with JRuby [#1091]

## 1.7.10 / 2017-02-03

* Changes and bug fixes
  * Address `TypeError: can't cast Java::JavaSql::Timestamp` [#1147, 1153]
  * Use docker-oracle-xe-11g for Travis CI for release17 branch [#1150]
  * Use JRuby 9.1.7.0 for release17 branch [#1154]
  * Pending until further investigation made for #908 for release17 branch [#1151]

* Known issues
 * No changes since 1.7.7

## 1.7.9 / 2016-12-26

* Changes and bug fixes

  * Fix ORA-00933 error when executing `rails db:schema:load` [#1084]
  * Quoting booleans should return a frozen string [#1083]
  * CI against ruby 2.4.0 [#1096, #1086]

* Known issues
 * No changes since 1.7.7

## 1.7.8 / 2016-12-06

* Changes and bug fixes
  * Separate schema migration insert statements correctly [#1074]
  * Add `use_old_oracle_visitor` example [#1068]
  * `supports_fetch_first_n_rows_and_offset?` returns `false` when `use_old_oracle_visitor` is true {1070, #1075]
  * Suppress `create_table(:posts, {:force=>true})` message [#1067, #1072]
  * Enable rubocop and Code Climate [#1056, #1057, #1060, #1062, #1071]
  * Bump MRI version for travis [#1054, #1059]
  * Drop `ActiveRecord::InternalMetadata.table_name` after each spec [#1073]

* Known issues
 * No changes since 1.7.7

## 1.7.7 / 2016-11-15

* Changes and bug fixes
  * Introduce `use_old_oracle_visitor` to choose old Oracle visitor [#1049]
  * Fix deprecated warnings in Ruby 2.4.0+ [#1048, #1052]
  * Add Ruby 2.2.5 and JRuby 9.0.5.0 for travis [#1050, #1051]

* Known issues
 * No changes since 1.7.6

## 1.7.6 / 2016-11-12

* Changes and bug fixes
  * Register `:boolean` type for Attribute API [#942, #1045]
  * No need to set version in Gemfile anymore since rdoc 5.0.0 released [#1040]
  * Bump MRI and JRuby version for travis [#1041, #1042, #1043]
* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]

## 1.7.5 / 2016-11-06

* Changes and bug fixes

 * Multi insert is not supported [#1016]
 * Use `default_timezone = :local` to handle `TIMESTAMP WITH LOCAL TIME ZONE` [#1001, #1019]
 * Address Rails 5 : custom methods for create record when exception is raised in `after_create` callback fails [#944, #1023]
 * Using the gem in non-rails apps [#1026]
 * Support connection strings in `DATABASE_URL1 [#1032, #1035]
 * Rebuild primary key index to `default_tablespaces[:index]` [#1028]
 * Address `Java::JavaSql::SQLException: Missing IN or OUT parameter at index:: 3:` [#1030, #1033]

* Known issues

 - Only with JRuby
 * Rails 5 : explain should explain query with binds got Java::JavaSql::SQLException: Invalid column index [#908]
    * Workaround: execute explain without bind or use CRuby
 - CRuby and JRuby
 * Rails 5 : specs need update to emulate_booleans_from_strings [#942]

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
 * Suppress WARNINGs using `raise_error` without specific errors [#724]
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
 * `describe` does not try super when no database link and ORA-4043 returned [#375]
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
    could be used simultaneously
  * Added Rails rake tasks as a copy from original oracle tasks
* Enhancements:
  * Improved performance of schema dump methods when used on large data dictionaries
  * Added LOB writing callback for sessions stored in database
  * Added emulate_dates_by_column_name option
  * Added emulate_integers_by_column_name option
  * Added emulate_booleans_from_strings option
