#!/bin/bash
# Entrypoint script for XtremFlow
# Fixes permissions on mounted volumes before starting the server

set -e

# PUID/PGID : faire tourner le serveur sous l'UID/GID de l'hôte (Unraid :
# 99/100 = nobody:users, comme Plex). Les enregistrements appartiennent alors
# au même utilisateur que les autres applis du partage.
if [ -n "$PGID" ] && [ "$PGID" != "$(id -g xtremuser)" ]; then
    echo "Using PGID=$PGID for xtremuser"
    groupmod -o -g "$PGID" xtremuser
fi
if [ -n "$PUID" ] && [ "$PUID" != "$(id -u xtremuser)" ]; then
    echo "Using PUID=$PUID for xtremuser"
    usermod -o -u "$PUID" xtremuser
fi

# Fichiers créés lisibles par tous (Plex, Jellyfin…), groupe en écriture.
umask "${UMASK:-002}"

# Fix ownership of data directory (runs as root initially)
echo "Fixing permissions on /app/data..."
chown -R xtremuser:xtremuser /app/data /tmp/xtremflow_streams 2>/dev/null || true

# Create subdirectories if they don't exist
mkdir -p /app/data/logs /app/data/tmp /app/recordings
chown -R xtremuser:xtremuser /app/data/logs /app/data/tmp /app/recordings 2>/dev/null || true
# Droits ajoutés, jamais retirés : un ancien `chmod 770` ôtait la lecture
# aux autres utilisateurs et Plex ne voyait plus les enregistrements.
chmod -R u+rwX,g+rwX /app/recordings 2>/dev/null || true

if ! gosu xtremuser test -w /app/recordings; then
    echo "AVERTISSEMENT: /app/recordings n'est pas accessible en écriture pour" \
        "l'UID $(id -u xtremuser) / GID $(id -g xtremuser) : les enregistrements" \
        "échoueront. Définir PUID/PGID sur le propriétaire du dossier hôte."
fi

# Drop privileges and run the server as xtremuser
echo "Starting server as xtremuser..."
exec gosu xtremuser "$@"
