#!/bin/bash

set -ev

${ORACLE_HOME}/bin/sqlplus system/${DATABASE_SYS_PASSWORD}@${CDB_NAME} <<SQL
set echo on
@@spec/support/modify_optimizer_features_enable.sql
exit
SQL
