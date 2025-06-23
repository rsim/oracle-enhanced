#!/bin/bash

set -ev

sqlplus sys/${DATABASE_SYS_PASSWORD}@${DATABASE_NAME} as sysdba<<SQL
@@spec/support/alter_system_set_open_cursors.sql
@@spec/support/create_oracle_enhanced_users.sql
exit
SQL
