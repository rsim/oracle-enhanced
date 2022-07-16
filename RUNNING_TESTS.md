[![Build Status](https://app.travis-ci.com/rsim/oracle-enhanced.svg?branch=master)](https://app.travis-ci.com/rsim/oracle-enhanced)

# When and Which tests need to be executed

When you are creating a fix and/or some new features for Oracle enhanced adapter,
It is recommended to execute Oracle enhanced adapter unit tests and ActiveRecord unit tests.

* Oracle enhanced adapter unit test
* ActiveRecord unit test

This document explains how to prepare and execute Oracle enhanced adapter unit test.
For ActiveRecord unit test, please refer [Contributing to Ruby on Rails](http://edgeguides.rubyonrails.org/contributing_to_ruby_on_rails.html) .

This document talks about developing Oracle enhanced adapter itself, does NOT talk about developing Rails applications using Oracle enhanced adapter.

# Building development and test environment

You can create Oracle enhanced adapter development and test environment by following one of them.  If you are first to create this environment
[rails-dev-box runs_oracle branch](https://github.com/yahonda/rails-dev-box/tree/runs_oracle) is recommended.

## [rails-dev-box runs_oracle branch](https://github.com/yahonda/rails-dev-box/tree/runs_oracle)
* Please follow the [README](https://github.com/yahonda/rails-dev-box/tree/runs_oracle#a-virtual-machine-for-ruby-on-rails-core-development-with-oracle-database) .

## [rails-dev-box runs_oracle19c_on_docker branch](https://github.com/yahonda/rails-dev-box/tree/runs_oracle19c_on_docker)
* Please follow the [README](https://github.com/yahonda/rails-dev-box/blob/runs_oracle19c_on_docker/README.md#a-virtual-machine-for-ruby-on-rails-core-development) .

## Create by yourself
You can create your development and test environment by yourself.

### Install Ruby
Install Ruby 2.2.2 or higher version of Ruby and JRuby 9.0.5 or higher. To switch multiple version of ruby, you can use use [ruby-build](https://github.com/rbenv/ruby-build) or [Ruby Version Manager(RVM)](https://rvm.io/).

### Creating the test database
To test Oracle enhanced adapter Oracle database is necesssary. You can build by your own or use the Docker to run pre-build Oracle Database Express Edition 11g Release 2.

#### Create database by yourself
Oracle database 11.2 or later with SYS and SYSTEM user access. AL32UTF8 database character set is recommended.

#### Docker
If no Oracle database with SYS and SYSTEM user access is available, try the docker approach.

* Install [Docker](https://docker.github.io/engine/installation/)

* Pull [docker-oracle-xe-11g-r2](https://hub.docker.com/r/wnameless/oracle-xe-11g-r2/) image from docker hub
  ```sh
  $ docker pull wnameless/oracle-xe-11g-r2
  ```

* Start a Oracle database docker container with mapped ports. Use port `49161` to access the database.
  ```sh
  $ docker run -d -p 49160:22 -p 49161:1521 wnameless/oracle-xe-11g-r2
  ```

* Check connection to the database with `sqlplus`. The user is `system`, the password is `oracle`.
  ```sh
  $ sqlplus64 system/oracle@localhost:49161
  ```


### Creating database schemas at the test database

* Create Oracle database schema for test purposes. Review `spec/spec_helper.rb` to see default schema/user names and database names (use environment variables to override defaults)

```sql
SQL> CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;
SQL> GRANT unlimited tablespace, create session, create table, create sequence, create procedure, create trigger, create view, create materialized view, create database link, create synonym, create type, ctxapp TO oracle_enhanced;

SQL> CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;
SQL> GRANT unlimited tablespace, create session, create table, create sequence, create procedure, create trigger, create view, create materialized view, create database link, create synonym, create type, ctxapp TO oracle_enhanced_schema;
```

### Configure database login credentials

* Configure database credentials in one of two ways:
    * copy `spec/spec_config.yaml.template` to `spec/spec_config.yaml` and modify as needed
    * set required environment variables (see DATABASE_NAME in spec_helper.rb)

* The oracle enhanced configuration file `spec/spec_config.yaml` should look like:

  ```yaml
  # copy this file to spec/config.yaml and set appropriate values
  # you can also use environment variables, see spec_helper.rb
  database:
    name:         'xe'
    host:         'localhost'
    port:         49161
    user:         'oracle_enhanced'
    password:     'oracle_enhanced'
    sys_password: 'oracle'
    non_default_tablespace: 'SYSTEM'
    timezone: 'Europe/Riga'
    ```

# Running Oracle enhanced adapter unit tests

* Install bundler
  ```sh
  $ gem install bundler
  ```

* Execute bundle install to install required gems
  ```sh
  $ bundle install
  ```

* Run Oracle enhanced adapter unit tests
  ```sh
  $ bundle exec rake spec
  ```
