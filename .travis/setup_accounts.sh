#!/bin/bash

set -ev

"$ORACLE_HOME/bin/sqlplus" -L -S / AS SYSDBA <<SQL
@@spec/support/alter_system_user_password.sql
@@spec/support/create_oracle_enhanced_users.sql
exit
SQL
