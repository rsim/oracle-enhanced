#!/bin/bash

set -e

gem update --system
bundle install

echo "Waiting for Oracle to be ready..."
oracle_ready=false
for i in $(seq 1 30); do
  if echo "exit" | sqlplus -s "system/${DATABASE_SYS_PASSWORD}@${DATABASE_NAME}" > /dev/null 2>&1; then
    oracle_ready=true
    break
  fi
  echo "Attempt $i/30 failed, retrying in 10s..."
  sleep 10
done
if [ "$oracle_ready" != "true" ]; then
  echo "Oracle did not become ready after 30 attempts; aborting container setup." >&2
  exit 1
fi

ci/setup_accounts.sh

echo "Dev container setup complete. You are ready to start developing the Oracle Enhanced adapter!"
