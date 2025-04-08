#!/bin/sh
# docker-entrypoint.sh

# Set strict error checking
set -e

# Take ownership of the data directory.
# This ensures the appuser can write to the volume.
# Use 'chown -R' if subdirectories might be created by the volume mount itself.
chown appuser:appuser /app/data

# Execute the original command (CMD) passed to the container
exec "$@"