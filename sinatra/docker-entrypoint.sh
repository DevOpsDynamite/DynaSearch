#!/bin/sh
# docker-entrypoint.sh

# Enable strict error handling
set -e

# Ensure the data directory is writable by the non-root user.
# If the mounted volume might not have correct permissions, this step is necessary.
chown appuser:appuser /app/data

# Drop privileges to run the CMD as appuser.
exec gosu appuser "$@"
