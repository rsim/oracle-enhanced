alter database default tablespace USERS;

CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp,
create public synonym, drop public synonym TO oracle_enhanced;

CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create type, ctxapp,
create public synonym, drop public synonym TO oracle_enhanced_schema;
