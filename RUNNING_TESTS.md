Creating the test database
--------------------------

You need Oracle database (version 10.2 or later) with SYS and SYSTEM user access.

If you are on a Mac OS X 10.6 then use [these instructions](http://blog.rayapps.com/2009/09/14/how-to-install-oracle-database-10g-on-mac-os-x-snow-leopard) to install local Oracle DB 10.2.0.4. Other option is to use Linux VM and install Oracle DB on it.

If you are on Linux (or will use Linux virtual machine) and need Oracle DB just for running tests then Oracle DB XE edition is enough. See [Oracle XE downloads page](http://www.oracle.com/technetwork/database/express-edition/downloads/index.html) for download links and instructions.

If you are getting ORA-12520 errors when running tests then it means that Oracle cannot create enough processes to handle many connections (as during tests many connections are created and destroyed). In this case you need to log in as SYSTEM user and execute e.g.

    alter system set processes=200 scope=spfile;

to increase process limit and then restart the database (this will be necessary if Oracle XE will be used as default processes limit is 40).

Ruby versions
-------------

oracle_enhanced is tested with MRI 2.1.x and 2.2.x, and JRuby 1.7.x and 9.0.x.x.  

It is recommended to use [RVM](http://rvm.beginrescueend.com) to run tests with different Ruby implementations.

Running tests
-------------

* Create Oracle database schema for test purposes. Review `spec/spec_helper.rb` to see default schema/user names and database names (use environment variables to override defaults)

        SQL> CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;
        SQL> GRANT unlimited tablespace, create session, create table, create sequence, create procedure, create trigger, create view, create materialized view, create database link, create synonym, create type, ctxapp TO oracle_enhanced;

        SQL> CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;
        SQL> GRANT unlimited tablespace, create session, create table, create sequence, create procedure, create trigger, create view, create materialized view, create database link, create synonym, create type, ctxapp TO oracle_enhanced_schema;

* If you use RVM then switch to corresponding Ruby. It is recommended to create isolated gemsets for test purposes (e.g. rvm create gemset oracle_enhanced)

* Install bundler with

        gem install bundler

* Install necessary gems with

        bundle install
        
* Configure database credentials in one of two ways:
    * copy spec/spec_config.yaml.template to spec/spec_config.yaml and modify as needed
    * set required environment variables (see DATABASE_NAME in spec_helper.rb)

* Run tests with

        rake spec
