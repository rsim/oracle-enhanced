#!/bin/bash

set -ev

/usr/lib/oracle/18.5/client64/bin/sqlplus system/Oracle18@XEPDB1 <<SQL
@@spec/support/alter_system_user_password.sql
@@spec/support/alter_system_set_open_cursors.sql
@@spec/support/create_oracle_enhanced_users.sql
exit
SQL
