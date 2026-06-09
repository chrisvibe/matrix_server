#!/bin/sh
# Restore a synapse_data tar backup produced by backup_data.sh into the data volume.
# Synapse MUST be stopped during this (the volume is replaced wholesale).
#
# Usage: restore_data.sh <backup_file.tar.gz>   (FORCE=1 or --force to skip confirmation)
set -eu

BACKUP_FILE="${1:-}"
FORCE="${FORCE:-0}"
[ "${2:-}" = "--force" ] && FORCE=1
DATA_DIR="${DATA_DIR:-/data}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    ls -lh "${BACKUP_DIR:-/backups}/${SERVICE_NAME:-matrix}_data_"*.tar.gz 2>/dev/null || echo "  (none found)"
    exit 1
fi
[ -f "$BACKUP_FILE" ] || { echo "ERROR: not found: $BACKUP_FILE"; exit 1; }

# Validate the archive BEFORE we wipe the live data.
gzip -t "$BACKUP_FILE" || { echo "ERROR: '$BACKUP_FILE' is not a valid gzip archive."; exit 1; }
tar tzf "$BACKUP_FILE" >/dev/null || { echo "ERROR: '$BACKUP_FILE' is not a valid tar archive."; exit 1; }

echo "=========================================="
echo " RESTORE synapse data -> ${DATA_DIR}"
echo " from    ${BACKUP_FILE}"
echo "=========================================="
echo "IMPORTANT: the synapse container must be STOPPED during this restore."
if [ "$FORCE" != "1" ]; then
    printf "Type 'yes' to proceed (this REPLACES everything in %s): " "$DATA_DIR"
    read -r CONFIRM
    [ "$CONFIRM" = "yes" ] || { echo "Cancelled."; exit 0; }
fi

log "Clearing ${DATA_DIR}..."
# Remove existing contents (including dotfiles) without deleting the mountpoint itself.
find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

log "Extracting archive..."
tar xzf "$BACKUP_FILE" -C "$DATA_DIR"

log "Restore complete. Start the synapse container again."
