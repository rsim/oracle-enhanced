alter database default tablespace USERS;

CREATE USER oracle_enhanced IDENTIFIED BY oracle_enhanced;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create public synonym, create type, ctxapp TO oracle_enhanced;
GRANT drop public synonym TO oracle_enhanced;

CREATE USER oracle_enhanced_schema IDENTIFIED BY oracle_enhanced_schema;

GRANT unlimited tablespace, create session, create table, create sequence,
create procedure, create trigger, create view, create materialized view,
create database link, create synonym, create public synonym, create type, ctxapp TO oracle_enhanced_schema;
GRANT drop public synonym TO oracle_enhanced_schema;

-- User for loopback database link tests.
-- The database link connects back to the same database authenticated as this
-- user, emulating a remote database without needing an external DB.
CREATE USER oracle_enhanced_remote IDENTIFIED BY oracle_enhanced_remote;

GRANT create session, create table, create sequence, create trigger,
unlimited tablespace TO oracle_enhanced_remote;
