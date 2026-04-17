alter database default tablespace USERS;

CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO oracle_enhanced;

CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO oracle_enhanced_schema;

-- User for multiple database (connected_to) tests.
CREATE USER oracle_enhanced_remote IDENTIFIED BY oracle_enhanced_remote;

GRANT create session, create table, create sequence, create trigger,
unlimited tablespace TO oracle_enhanced_remote;
