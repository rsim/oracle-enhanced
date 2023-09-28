#!/bin/bash

set -ev

sqlplus system/${DATABASE_SYS_PASSWORD}@${DATABASE_NAME} <<SQL
@@spec/support/alter_system_set_open_cursors.sql
@@spec/support/create_oracle_enhanced_users.sql
exit
SQL
