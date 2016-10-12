activerecord-oracle_enhanced-adapter
====================================

Oracle enhanced adapter for ActiveRecord

DESCRIPTION
-----------

Oracle enhanced ActiveRecord adapter provides Oracle database access from Ruby on Rails applications. Oracle enhanced adapter can be used from Ruby on Rails versions between 2.3.x and 5.0 and it is working with Oracle database versions from 10g to 12c.

INSTALLATION
------------
### Rails 5.0

Oracle enhanced adapter version 1.7 just supports Rails 5.0 and does not support Rails 4.2 or lower version of Rails.
When using Ruby on Rails version 5.0 then in Gemfile include

```ruby
# Use oracle as the database for Active Record
gem 'activerecord-oracle_enhanced-adapter', '~> 1.7.0'
gem 'ruby-oci8' # only for CRuby users
```

### Rails 4.2

Oracle enhanced adapter version 1.6 just supports Rails 4.2 and does not support Rails 4.1 or lower version of Rails.
When using Ruby on Rails version 4.2 then in Gemfile include

```ruby
gem 'activerecord-oracle_enhanced-adapter', '~> 1.6.0'
```

where instead of 1.6.0 you can specify any other desired version. It is recommended to specify version with `~>` which means that use specified version or later patch versions (in this example any later 1.6.x version but not 1.7.x version). Oracle enhanced adapter maintains API backwards compatibility during patch version upgrades and therefore it is safe to always upgrade to latest patch version.

### Rails 4.0 and 4.1

Oracle enhanced adapter version 1.5 supports Rails 4.0 and 4.1 and does not support Rails 3.2 or lower version of Rails.

When using Ruby on Rails version 4.0 and 4.1 then in Gemfile include

```ruby
gem 'activerecord-oracle_enhanced-adapter', '~> 1.5.0'
```

where instead of 1.5.0 you can specify any other desired version. It is recommended to specify version with `~>` which means that use specified version or later patch versions (in this example any later 1.5.x version but not 1.6.x version). Oracle enhanced adapter maintains API backwards compatibility during patch version upgrades and therefore it is safe to always upgrade to latest patch version.

If you would like to use latest adapter version from github then specify

```ruby
gem 'activerecord-oracle_enhanced-adapter', :git => 'git://github.com/rsim/oracle-enhanced.git'
```

If you are using CRuby >= 1.9.3 then you need to install ruby-oci8 gem as well as Oracle client, e.g. [Oracle Instant Client](http://www.oracle.com/technetwork/database/features/instant-client/index-097480.html). Include in Gemfile also ruby-oci8:

```ruby
gem 'ruby-oci8', '~> 2.1.0'
```

If you are using JRuby then you need to download latest [Oracle JDBC driver](http://www.oracle.com/technetwork/database/enterprise-edition/jdbc-112010-090769.html) - either ojdbc7.jar or ojdbc6.jar for Java 7, ojdbc6.jar for Java 6 or ojdbc5.jar for Java 5. And copy this file to one of these locations:

  * in `./lib` directory of Rails application
  * in some directory which is in `PATH`
  * in `JRUBY_HOME/lib` directory
  * or include path to JDBC driver jar file in Java `CLASSPATH`

After specifying necessary gems in Gemfile run

```bash
bundle install
```

to install the adapter (or later run `bundle update` to force updating to latest version).

### Rails 3

When using Ruby on Rails version 3 then in Gemfile include

```ruby
gem 'activerecord-oracle_enhanced-adapter', '~> 1.4.0'
```

where instead of 1.4.0 you can specify any other desired version. It is recommended to specify version with `~>` which means that use specified version or later patch versions (in this example any later 1.4.x version but not 1.5.x version). Oracle enhanced adapter maintains API backwards compatibility during patch version upgrades and therefore it is safe to always upgrade to latest patch version.

If you would like to use latest adapter version from github then specify

```ruby
gem 'activerecord-oracle_enhanced-adapter', :git => 'git://github.com/rsim/oracle-enhanced.git'
```

If you are using MRI 1.8 or 1.9 Ruby implementation then you need to install ruby-oci8 gem as well as Oracle client, e.g. [Oracle Instant Client](http://www.oracle.com/technetwork/database/features/instant-client/index-097480.html). Include in Gemfile also ruby-oci8:

```ruby
gem 'ruby-oci8', '~> 2.1.0'
```

If you are using JRuby then you need to download latest [Oracle JDBC driver](http://www.oracle.com/technetwork/database/enterprise-edition/jdbc-112010-090769.html) - either ojdbc6.jar for Java 6 or ojdbc5.jar for Java 5. And copy this file to one of these locations:

  * in `./lib` directory of Rails application
  * in some directory which is in `PATH`
  * in `JRUBY_HOME/lib` directory
  * or include path to JDBC driver jar file in Java `CLASSPATH`

After specifying necessary gems in Gemfile run

```bash
bundle install
```

to install the adapter (or later run `bundle update` to force updating to latest version).

### Rails 2.3

If you don't use Bundler in Rails 2 application then you need to specify gems in `config/environment.rb`, e.g.

```ruby
Rails::Initializer.run do |config|
  # ...
  config.gem 'activerecord-oracle_enhanced-adapter', :lib => 'active_record/connection_adapters/oracle_enhanced_adapter'
  config.gem 'ruby-oci8'
  # ...
end
```

But it is recommended to use Bundler for gem version management also for Rails 2.3 applications (search for instructions in Google).

### Without Rails and Bundler

If you want to use ActiveRecord and Oracle enhanced adapter without Rails and Bundler then install it just as a gem:

```bash
gem install activerecord-oracle_enhanced-adapter
```

USAGE
-----

### Database connection

In Rails application `config/database.yml` use oracle_enhanced as adapter name, e.g.

```yml
development:
  adapter: oracle_enhanced
  database: xe
  username: user
  password: secret
```

If you're connecting to a service name, indicate the service with a
leading slash on the database parameter:

```yml
development:
  adapter: oracle_enhanced
  database: /xe
  username: user
  password: secret
```

If `TNS_ADMIN` environment variable is pointing to directory where `tnsnames.ora` file is located then you can use TNS connection name in `database` parameter. Otherwise you can directly specify database host, port (defaults to 1521) and database name in the following way:

```yml
development:
  adapter: oracle_enhanced
  host: localhost
  port: 1521
  database: xe
  username: user
  password: secret
```

or you can use Oracle specific format in `database` parameter:

```yml
development:
  adapter: oracle_enhanced
  database: //localhost:1521/xe
  username: user
  password: secret
```

or you can even use Oracle specific TNS connection description:

```yml
development:
  adapter: oracle_enhanced
  database: "(DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521)))
    (CONNECT_DATA=(SERVICE_NAME=xe))
  )"
  username: user
  password: secret
```


If you choose to specify your database connection via the `DATABASE_URL`
environment variable, note that the adapter name uses a dash instead of an underscore:

```bash
DATABASE_URL=oracle-enhanced://localhost/XE
```

If you deploy JRuby on Rails application in Java application server that supports JNDI connections then you can specify JNDI connection as well:

```yml
development:
  adapter: oracle_enhanced
  jndi: "jdbc/jndi_connection_name"
```

To use jndi with Tomcat you need to set the accessToUnderlyingConnectionAllowed to true property on the pool. See  the [Tomcat Documentation](http://tomcat.apache.org/tomcat-7.0-doc/jndi-resources-howto.html) for reference.

You can find other available database.yml connection parameters in [oracle_enhanced_adapter.rb](http://github.com/rsim/oracle-enhanced/blob/master/lib/active_record/connection_adapters/oracle_enhanced_adapter.rb). There are many NLS settings as well as some other Oracle session settings.

### Adapter settings

If you want to change Oracle enhanced adapter default settings then create initializer file e.g. `config/initializers/oracle.rb` specify there necessary defaults, e.g.:

```ruby
# It is recommended to set time zone in TZ environment variable so that the same timezone will be used by Ruby and by Oracle session
ENV['TZ'] = 'UTC'

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
    # id columns and columns which end with _id will always be converted to integers
    self.emulate_integers_by_column_name = true

    # DATE columns which include "date" in name will be converted to Date, otherwise to Time
    self.emulate_dates_by_column_name = true

    # true and false will be stored as 'Y' and 'N'
    self.emulate_booleans_from_strings = true

    # start primary key sequences from 1 (and not 10000) and take just one next value in each session
    self.default_sequence_start_value = "1 NOCACHE INCREMENT BY 1"

    # other settings ...
  end
end
```

In case of Rails 2 application you do not need to use `ActiveSupport.on_load(:active_record) do ... end` around settings code block.

See other adapter settings in [oracle_enhanced_adapter.rb](http://github.com/rsim/oracle-enhanced/blob/master/lib/active_record/connection_adapters/oracle_enhanced_adapter.rb).

### Legacy schema support

If you want to put Oracle enhanced adapter on top of existing schema tables then there are several methods how to override ActiveRecord defaults, see example:

```ruby
class Employee < ActiveRecord::Base
  # specify schema and table name
  self.table_name = "hr.hr_employees"

  # specify primary key name
  self.primary_key = "employee_id"

  # specify sequence name
  self.sequence_name = "hr.hr_employee_s"

  # set which DATE columns should be converted to Ruby Date using ActiveRecord Attribute API
  # Starting from Oracle enhanced adapter 1.7 Oracle `DATE` columns are mapped to Ruby `Date` by default.
  attribute :hired_on, :date
  attribute :birth_date_on, :date

  # set which DATE columns should be converted to Ruby Time using ActiveRecord Attribute API
  attribute :last_login_time, :datetime

  # set which VARCHAR2 columns should be converted to true and false using ActiveRecord Attribute API
  attribute :manager, :boolean
  attribute :active, :boolean

  # set which columns should be ignored in ActiveRecord
  ignore_table_columns :attribute1, :attribute2
end
```

You can also access remote tables over database link using

```ruby
self.table_name "hr_employees@db_link"
```

Examples for Rails 4.x

```ruby
class Employee < ActiveRecord::Base
  # specify schema and table name
  self.table_name = "hr.hr_employees"

  # specify primary key name
  self.primary_key = "employee_id"

  # specify sequence name
  self.sequence_name = "hr.hr_employee_s"

  # If you're using Rails 4.2 or earlier you can do this

  # set which DATE columns should be converted to Ruby Date
  set_date_columns :hired_on, :birth_date_on

  # set which DATE columns should be converted to Ruby Time
  set_datetime_columns :last_login_time

  # set which VARCHAR2 columns should be converted to true and false
  set_boolean_columns :manager, :active

  # set which columns should be ignored in ActiveRecord
  ignore_table_columns :attribute1, :attribute2
end
```

Examples for Rails 3.2 and lower version of Rails

```ruby
class Employee < ActiveRecord::Base
  # specify schema and table name
  set_table_name "hr.hr_employees"

  # specify primary key name
  set_primary_key "employee_id"

  # specify sequence name
  set_sequence_name "hr.hr_employee_s"

  # set which DATE columns should be converted to Ruby Date
  set_date_columns :hired_on, :birth_date_on

  # set which DATE columns should be converted to Ruby Time
  set_datetime_columns :last_login_time

  # set which VARCHAR2 columns should be converted to true and false
  set_boolean_columns :manager, :active

  # set which columns should be ignored in ActiveRecord
  ignore_table_columns :attribute1, :attribute2
end
```

You can also access remote tables over database link using

```ruby
set_table_name "hr_employees@db_link"
```

### Custom create, update and delete methods

If you have legacy schema and you are not allowed to do direct INSERTs, UPDATEs and DELETEs in legacy schema tables and need to use existing PL/SQL procedures for create, updated, delete operations then you should add `ruby-plsql` gem to your application, include `ActiveRecord::OracleEnhancedProcedures` in your model and then define custom create, update and delete methods, see example:

```ruby
class Employee < ActiveRecord::Base
  include ActiveRecord::OracleEnhancedProcedures

  # when defining create method then return ID of new record that will be assigned to id attribute of new object
  set_create_method do
    plsql.employees_pkg.create_employee(
      :p_first_name => first_name,
      :p_last_name => last_name,
      :p_employee_id => nil
    )[:p_employee_id]
  end

  set_update_method do
    plsql.employees_pkg.update_employee(
      :p_employee_id => id,
      :p_first_name => first_name,
      :p_last_name => last_name
    )
  end

  set_delete_method do
    plsql.employees_pkg.delete_employee(
      :p_employee_id => id
    )
  end
end
```

In addition in `config/initializers/oracle.rb` initializer specify that ruby-plsql should use ActiveRecord database connection:

```ruby
plsql.activerecord_class = ActiveRecord::Base
```

### Oracle CONTEXT index support

Every edition of Oracle database includes [Oracle Text](http://www.oracle.com/technology/products/text/index.html) option for free which provides several full text indexing capabilities. Therefore in Oracle database case you don’t need external full text indexing and searching engines which can simplify your application deployment architecture.

To create simple single column index create migration with, e.g.

```ruby
add_context_index :posts, :title
```

and you can remove context index with

```ruby
remove_context_index :posts, :title
```

Include in class definition

```ruby
has_context_index
```

and then you can do full text search with

```ruby
Post.contains(:title, 'word')
```

You can create index on several columns (which will generate additional stored procedure for providing XML document with specified columns to indexer):

```ruby
add_context_index :posts, [:title, :body]
```

And you can search either in all columns or specify in which column you want to search (as first argument you need to specify first column name as this is the column which is referenced during index creation):

```ruby
Post.contains(:title, 'word')
Post.contains(:title, 'word within title')
Post.contains(:title, 'word within body')
```

See Oracle Text documentation for syntax that you can use in CONTAINS function in SELECT WHERE clause.

You can also specify some dummy main column name when creating multiple column index as well as specify to update index automatically after each commit (as otherwise you need to synchronize index manually or schedule periodic update):

```ruby
add_context_index :posts, [:title, :body], :index_column => :all_text, :sync => 'ON COMMIT'

Post.contains(:all_text, 'word')
```

Or you can specify that index should be updated when specified columns are updated (e.g. in ActiveRecord you can specify to trigger index update when created_at or updated_at columns are updated). Otherwise index is updated only when main index column is updated.

```ruby
add_context_index :posts, [:title, :body], :index_column => :all_text,
  :sync => 'ON COMMIT', :index_column_trigger_on => [:created_at, :updated_at]
```

And you can even create index on multiple tables by providing SELECT statements which should be used to fetch necessary columns from related tables:

```ruby
add_context_index :posts,
  [:title, :body,
  # specify aliases always with AS keyword
  "SELECT comments.author AS comment_author, comments.body AS comment_body FROM comments WHERE comments.post_id = :id"
  ],
  :name => 'post_and_comments_index',
  :index_column => :all_text,
  :index_column_trigger_on => [:updated_at, :comments_count],
  :sync => 'ON COMMIT'

# search in any table columns
Post.contains(:all_text, 'word')
# search in specified column
Post.contains(:all_text, "aaa within title")
Post.contains(:all_text, "bbb within comment_author")
```

Please note that `index_column` must be a real column in your database and it's value will be overriden every time your `index_column_trigger_on` columns are changed. So, _do not use columns with real data as `index_column`_.

Index column can be created as:

```ruby
add_column :posts, :all_text, :string, limit: 2, comment: 'Service column for context search index'
```

### Oracle virtual columns support

Since version R11G1 Oracle database allows adding computed [Virtual Columns](http://www.oracle-base.com/articles/11g/virtual-columns-11gr1.php) to the table.
They can be used as normal fields in the queries, in the foreign key contstraints and to partitioning data.

To define virtual column you can use `virtual` method in the `create_table` block, providing column expression in the `:as` option:

```ruby
create_table :mytable do |t|
  t.decimal :price, :precision => 15, :scale => 2
  t.decimal :quantity, :precision => 15, :scale => 2
  t.virtual :amount, :as => 'price * quantity'
end
```

Oracle tries to predict type of the virtual column, based on its expression but sometimes it is necessary to state type explicitly.
This can be done by providing `:type` option to the `virtual` method:

```ruby
# ...
t.virtual :amount_2, :as => 'ROUND(price * quantity,2)', :type => :decimal, :precision => 15, :scale => 2
t.virtual :amount_str, :as => "TO_CHAR(quantity) || ' x ' || TO_CHAR(price) || ' USD = ' || TO_CHAR(quantity*price) || ' USD'",
    :type => :string, :limit => 100
# ...
```

It is possible to add virtual column to existing table:

```ruby
add_column :mytable, :amount_4, :virtual, :as => 'ROUND(price * quantity,4)', :precision => 38, :scale => 4
```

You can use the same options here as in the `create_table` `virtual` method.

Changing virtual columns is also possible:

```ruby
change_column :mytable, :amount, :virtual, :as => 'ROUND(price * quantity,0)', :type => :integer
```

Virtual columns allowed in the foreign key constraints.
For example it can be used to force foreign key constraint on polymorphic association:

```ruby
create_table :comments do |t|
  t.string :subject_type
  t.integer :subject_id
  t.virtual :subject_photo_id, :as => "CASE subject_type WHEN 'Photo' THEN subject_id END"
  t.virtual :subject_event_id, :as => "CASE subject_type WHEN 'Event' THEN subject_id END"
end

add_foreign_key :comments, :photos, :column => :subject_photo_id
add_foreign_key :comments, :events, :column => :subject_event_id
```

For backward compatibility reasons it is possible to use `:default` option in the `create_table` instead of `:as` option.
But this is deprecated and may be removed in the future version.

### Oracle specific schema statements and data types

There are several additional schema statements and data types available that you can use in database migrations:

  * `add_foreign_key` and `remove_foreign_key` for foreign key definition (and they are also dumped in `db/schema.rb`)
  * `add_synonym` and `remove_synonym` for synonym definition (and they are also dumped in `db/schema.rb`)
  * You can create table with primary key trigger using `:primary_key_trigger => true` option for `create_table`
  * You can define columns with `raw` type which maps to Oracle's `RAW` type
  * You can add table and column comments with `:comment` option
  * Default tablespaces can be specified for tables, indexes, clobs and blobs, for example:

```ruby
ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_tablespaces =
  {:clob => 'TS_LOB', :blob => 'TS_LOB', :index => 'TS_INDEX', :table => 'TS_DATA'}
```

### Switching to another schema

There are some requirements to connect to Oracle database first and switch to another user.
Oracle enhanced adapter supports schema: option.

Note: Oracle enhanced adapter does not take care if the database user specified in username: parameter
has appropriate privilege to select, insert, update and delete database objects owned by the schema specified in schema: parameter.

```yml
development:
  adapter: oracle_enhanced
  database: xe
  username: user
  password: secret
  schema: tableowner
```

### Timeouts

By default, OCI libraries set a connect timeout of 60 seconds (as of v12.0), and do not set a data receive timeout.

While this may desirable if you process queries that take several minutes to complete, it may also lead to resource exhaustion if
connections are teared down improperly during a query, e.g. by misbehaving networking equipment that does not inform both peers of
connection reset. In this scenario, the OCI libraries will wait indefinitely for data to arrive, thus blocking indefinitely the application
that initiated the query.

You can set a connect timeout, in seconds, using the following TNSNAMES parameters:

  * `CONNECT_TIMEOUT`
  * `TCP_CONNECT_TIMEOUT`

Example setting a 5 seconds connect timeout:

```yml
development:
  database: "(DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521)))
    (CONNECT_TIMEOUT=5)(TCP_CONNECT_TIMEOUT=5)
    (CONNECT_DATA=(SERVICE_NAME=xe))
  )"
```
You should set a timeout value dependant on your network topology, and the time needed to establish a TCP connection with your ORACLE
server. In real-world scenarios, a value larger than 5 should be avoided.

You can set receive and send timeouts, in seconds, using the following TNSNAMES parameters:

  * `RECV_TIMEOUT` - the maximum time the OCI libraries should wait for data to arrive on the TCP socket. Internally, it is implemented
    through a `setsockopt(s, SOL_SOCKET, SO_RCVTIMEO)`. You should set this value to an integer larger than the server-side execution time
    of your longest-running query.
  * `SEND_TIMEOUT` the maximum time the OCI libraries should wait for write operations to complete on the TCP socket. Internally, it is
    implemented through a `setsockopt(s, SOL_SOCKET, SO_SNDTIMEO)`. Values larger than 5 are a sign of poorly performing network, and as
    such it should be avoided.

Example setting a 60 seconds receive timeout and 5 seconds send timeout:

```yml
development:
  database: "(DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521)))
    (RECV_TIMEOUT=60)(SEND_TIMEOUT=5)
    (CONNECT_DATA=(SERVICE_NAME=xe))
  )"
```

Example setting the above send/recv timeout plus a 5 seconds connect timeout:

```yml
development:
  database: "(DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521)))
    (CONNECT_TIMEOUT=5)(TCP_CONNECT_TIMEOUT=5)
    (RECV_TIMEOUT=60)(SEND_TIMEOUT=5)
    (CONNECT_DATA=(SERVICE_NAME=xe))
  )"
```

UPGRADE
---------------
### Upgrade Rails 4.2 or older version to Rails 5

If your Oracle table columns have been created for Rails `:datetime` attributes in Rails 4.2 or earlier,
they need to migrate to `:datetime` in Rails 5 using one of two following ways:

* Rails migration code example:
```ruby
change_column :posts, :created_at, :datetime
change_column :posts, :updated_at, :datetime
```

or

* SQL statement example
```sql
ALTER TABLE "POSTS" MODIFY "CREATED_AT" TIMESTAMP
ALTER TABLE "POSTS" MODIFY "UPDATED_AT" TIMESTAMP
```

In Rails 5 without running this migration or sql statement, 
these attributes will be handled as Rails `:date` type.

TROUBLESHOOTING
---------------

### What to do if Oracle enhanced adapter is not working?

Please verify that

 1. Oracle Instant Client is installed correctly
    Can you connect to database using sqlnet?

 2. ruby-oci8 is installed correctly
    Try something like:

        ruby -rubygems -e "require 'oci8'; OCI8.new('username','password','database').exec('select * from dual') do |r| puts r.join(','); end"

    to verify that ruby-oci8 is working

 3. Verify that activerecord-oracle_enhanced-adapter is working from irb

```ruby
require 'rubygems'
gem 'activerecord'
gem 'activerecord-oracle_enhanced-adapter'
require 'active_record'
ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced", :database => "database",:username => "user",:password => "password")
```

and see if it is successful (use your correct database, username and password)

### What to do if Oracle enhanced adapter is not working with Phusion Passenger?

Oracle Instant Client and ruby-oci8 requires that several environment variables are set:

  * `LD_LIBRARY_PATH` (on Linux) or `DYLD_LIBRARY_PATH` (on Mac) should point to Oracle Instant Client directory (where Oracle client shared libraries are located)
  * `TNS_ADMIN` should point to directory where `tnsnames.ora` file is located
  * `NLS_LANG` should specify which territory and language NLS settings to use and which character set to use (e.g. `"AMERICAN_AMERICA.UTF8"`)

If this continues to throw "OCI Library Initialization Error (OCIError)", you might also need

  * `ORACLE_HOME` set to full Oracle client installation directory

When Apache with Phusion Passenger (mod_passenger or previously mod_rails) is used for Rails application deployment then by default Ruby is launched without environment variables that you have set in shell profile scripts (e.g. .profile). Therefore it is necessary to set environment variables in one of the following ways:

  * Create wrapper script as described in [Phusion blog](http://blog.phusion.nl/2008/12/16/passing-environment-variables-to-ruby-from-phusion-passenger) or [RayApps::Blog](http://blog.rayapps.com/2008/05/21/using-mod_rails-with-rails-applications-on-oracle)
  * Set environment variables in the file which is used by Apache before launching Apache worker processes - on Linux it typically is envvars file (look in apachectl or apache2ctl script where it is looking for envvars file) or /System/Library/LaunchDaemons/org.apache.httpd.plist on Mac OS X. See the following [discussion thread](http://groups.google.com/group/oracle-enhanced/browse_thread/thread/c5f64106569fadd0) for more hints.

### What to do if my application is stuck?

If you see established TCP connections that do not exchange data, and you are unable to terminate your application using a TERM or an INT
signal, and you are forced to use the KILL signal, then the OCI libraries may be waiting indefinitely for a network read operation to
complete.

See the **Timeouts** section above.

RUNNING TESTS
-------------

See [RUNNING_TESTS.md](https://github.com/rsim/oracle-enhanced/blob/master/RUNNING_TESTS.md) for information how to set up environment and run Oracle enhanced adapter unit tests.

LINKS
-----

* Source code: http://github.com/rsim/oracle-enhanced
* Bug reports / Feature requests / Pull requests: http://github.com/rsim/oracle-enhanced/issues
* Discuss at Oracle enhanced adapter group: http://groups.google.com/group/oracle-enhanced
* Blog posts about Oracle enhanced adapter can be found at http://blog.rayapps.com/category/oracle_enhanced

LICENSE
-------

(The MIT License)

Copyright (c) 2008-2011 Graham Jenkins, Michael Schoen, Raimonds Simanovskis

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
