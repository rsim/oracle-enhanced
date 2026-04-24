activerecord-oracle_enhanced-adapter
====================================

[![test](https://github.com/rsim/oracle-enhanced/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/rsim/oracle-enhanced/actions/workflows/test.yml)

Oracle enhanced adapter for ActiveRecord

DESCRIPTION
-----------

Oracle enhanced ActiveRecord adapter provides Oracle database access from Ruby on Rails applications. This branch supports Ruby on Rails 8.1 and is tested with Oracle Database 11g Release 2 (11.2) and higher. For earlier Rails versions, see the corresponding release branch or Git tag.

INSTALLATION
------------

Oracle enhanced adapter version 8.1 supports Rails 8.1. In `Gemfile`:

```ruby
# Use oracle as the database for Active Record
gem 'activerecord-oracle_enhanced-adapter', '~> 8.1.0'
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

You can also specify a connection string via the `DATABASE_URL`, as long as it doesn't have any whitespace:

```bash
DATABASE_URL=oracle-enhanced://user:secret@connection-string/(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521)))(CONNECT_DATA=(SERVICE_NAME=xe)))
```

If you deploy JRuby on Rails application in Java application server that supports JNDI connections then you can specify JNDI connection as well:

```yml
development:
  adapter: oracle_enhanced
  jndi: "jdbc/jndi_connection_name"
```

To use jndi with Tomcat you need to set the accessToUnderlyingConnectionAllowed to true property on the pool. See  the [Tomcat Documentation](http://tomcat.apache.org/tomcat-7.0-doc/jndi-resources-howto.html) for reference.

You can find other available database.yml connection parameters in [oracle_enhanced_adapter.rb](https://github.com/rsim/oracle-enhanced/blob/master/lib/active_record/connection_adapters/oracle_enhanced_adapter.rb). There are many NLS settings as well as some other Oracle session settings.

### Adapter settings

If you want to change Oracle enhanced adapter default settings then create initializer file e.g. `config/initializers/oracle.rb` specify there necessary defaults, e.g.:

```ruby
# It is recommended to set time zone in TZ environment variable so that the same timezone will be used by Ruby and by Oracle session
ENV['TZ'] = 'UTC'

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.class_eval do
    # true and false will be stored as 'Y' and 'N'
    self.emulate_booleans_from_strings = true

    # start primary key sequences from 1 (and not 10000) and take just one next value in each session
    self.default_sequence_start_value = "1 NOCACHE INCREMENT BY 1"

    # Use old visitor for Oracle 12c database
    self.use_old_oracle_visitor = true

    # other settings ...
  end
end
```

In case of Rails 2 application you do not need to use `ActiveSupport.on_load(:active_record) do ... end` around settings code block.

See other adapter settings in [oracle_enhanced_adapter.rb](https://github.com/rsim/oracle-enhanced/blob/master/lib/active_record/connection_adapters/oracle_enhanced_adapter.rb).

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

### Accessing remote tables over a database link

Setting `self.table_name = "hr_employees@db_link"` directly is **not
supported**. The adapter strips the `@db_link` suffix during identifier
quoting, so the generated SQL silently queries a local table of the same
name; some code paths additionally raise `ArgumentError: db link is not
supported`.

When the Rails application can connect to the remote database directly,
the recommended approach is [Rails multiple-database
support](https://guides.rubyonrails.org/active_record_multiple_databases.html):
configure a separate connection for the remote database and inherit the
model from a dedicated abstract class connected to it.

When a direct connection is not possible and a database link is the only
available path, create a local synonym (private in the Rails connection's
schema, or a public synonym) that points at the remote table through the
database link, and use the synonym as `table_name`:

```sql
CREATE SYNONYM hr_employees_syn FOR hr_employees@db_link;
```

```ruby
class Employee < ActiveRecord::Base
  self.table_name = "hr_employees_syn"
end
```

Oracle resolves the synonym through the database link transparently, so
the adapter never sees an `@` in the identifier.

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

Please note that `index_column` must be a real column in your database and it's value will be overridden every time your `index_column_trigger_on` columns are changed. So, _do not use columns with real data as `index_column`_.

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

### Schema cache

`rails db:schema:cache:dump` generates `db/schema_cache.yml` to avoid queries for Oracle database dictionary, which could help your application response time if it takes time to look up database structure.

if any database structure changed by migrations, execute `rails db:schema:cache:dump` again and restart Rails server to reflect changes.

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

### Required environment variables for Oracle Instant Client

Oracle Instant Client and ruby-oci8 require that several environment variables be set:

  * `LD_LIBRARY_PATH` (on Linux) or `DYLD_LIBRARY_PATH` (on Mac) should point to the Oracle Instant Client directory (where Oracle client shared libraries are located)
  * `TNS_ADMIN` should point to the directory where `tnsnames.ora` is located
  * `NLS_LANG` should specify territory, language, and character set (e.g. `"AMERICAN_AMERICA.UTF8"`)
  * If you still see "OCI Library Initialization Error (OCIError)", also set `ORACLE_HOME` to the full Oracle client installation directory.

### What to do if my application is stuck?

If you see established TCP connections that do not exchange data, and you are unable to terminate your application using a TERM or an INT
signal, and you are forced to use the KILL signal, then the OCI libraries may be waiting indefinitely for a network read operation to
complete.

See the **Timeouts** section above.

CONTRIBUTING
------------

See [CONTRIBUTING.md](https://github.com/rsim/oracle-enhanced/blob/master/CONTRIBUTING.md) for how to report issues, submit pull requests, and set up the devcontainer-based development environment.

LINKS
-----

* Source code: https://github.com/rsim/oracle-enhanced
* Issues / Pull requests: https://github.com/rsim/oracle-enhanced/issues

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
