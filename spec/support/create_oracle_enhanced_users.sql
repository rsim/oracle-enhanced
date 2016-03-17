CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO oracle_enhanced;

CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO oracle_enhanced_schema;

CREATE USER arunit IDENTIFIED BY arunit;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO arunit;

CREATE USER arunit2 IDENTIFIED BY arunit2;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp TO arunit2;

CREATE USER ruby IDENTIFIED BY oci8;
GRANT connect, resource, create view,create synonym TO ruby;
GRANT EXECUTE ON dbms_lock TO ruby;
GRANT CREATE VIEW TO ruby;
GRANT unlimited tablespace to ruby;
