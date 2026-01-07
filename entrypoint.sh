#!/bin/bash
# Entrypoint script for XtremFlow
# Fixes permissions on mounted volumes before starting the server

set -e

# Fix ownership of data directory (runs as root initially)
echo "Fixing permissions on /app/data..."
chown -R xtremuser:xtremuser /app/data 2>/dev/null || true

# Create subdirectories if they don't exist
mkdir -p /app/data/logs /app/data/tmp
chown -R xtremuser:xtremuser /app/data/logs /app/data/tmp 2>/dev/null || true

# Drop privileges and run the server as xtremuser
echo "Starting server as xtremuser..."
exec gosu xtremuser "$@"
