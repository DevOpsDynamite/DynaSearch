#!/bin/sh

# Enable strict error handling
set -e

# Ensure the data directory AND ITS CONTENTS are writable by the non-root user.
# Use -R for recursive ownership change.
chown -R appuser:appuser /app/data
mkdir -p /app/log
chown -R appuser:appuser /app/log

# Drop privileges to run the CMD as appuser.
exec gosu appuser "$@"