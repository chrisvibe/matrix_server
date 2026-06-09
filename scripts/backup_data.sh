#!/bin/sh
# Tar backup of a data volume (matrix synapse_data: media store, signing keys, logs config).
# Synapse keeps its media + homeserver signing key on disk, NOT in Postgres, so the DB dump
# alone is not a complete matrix backup — this captures the rest.
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
SERVICE_NAME="${SERVICE_NAME:-matrix}"
DATA_DIR="${DATA_DIR:-/data}"   # the volume to archive, mounted read-only

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${SERVICE_NAME}_data_${TIMESTAMP}.tar.gz"

trap 'rm -f "${BACKUP_FILE}.tmp"' EXIT

log "Archiving ${DATA_DIR} -> ${BACKUP_FILE}"
tar czf "${BACKUP_FILE}.tmp" -C "$DATA_DIR" .
gzip -t "${BACKUP_FILE}.tmp"            # verify the gzip stream is complete
mv "${BACKUP_FILE}.tmp" "$BACKUP_FILE"  # atomic publish

log "Backup OK: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"

DELETED=$(find "$BACKUP_DIR" -name "${SERVICE_NAME}_data_*.tar.gz" -type f -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
REMAINING=$(find "$BACKUP_DIR" -name "${SERVICE_NAME}_data_*.tar.gz" -type f | wc -l)
log "Retention ${RETENTION_DAYS}d: pruned ${DELETED}, ${REMAINING} archive(s) remain"
