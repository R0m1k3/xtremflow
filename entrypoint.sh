#!/bin/bash
# Entrypoint script for XtremFlow
# Fixes permissions on mounted volumes before starting the server

set -e

# Fix ownership of data directory (runs as root initially)
echo "Fixing permissions on /app/data..."
chown -R xtremuser:xtremuser /app/data 2>/dev/null || true

# Create subdirectories if they don't exist
mkdir -p /app/data/logs /app/data/tmp /app/recordings
chown -R xtremuser:xtremuser /app/data/logs /app/data/tmp /app/recordings 2>/dev/null || true
# Garantir les permissions en écriture (770 si chown a réussi, 775 en
# secours pour les volumes hôtes avec un UID différent — jamais 777)
if chown -R xtremuser:xtremuser /app/recordings 2>/dev/null; then
    chmod -R 770 /app/recordings 2>/dev/null || true
else
    chmod -R 775 /app/recordings 2>/dev/null || true
fi

# Drop privileges and run the server as xtremuser
echo "Starting server as xtremuser..."
exec gosu xtremuser "$@"
