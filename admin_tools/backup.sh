#!/bin/bash

# Matrix Server Backup Script

# Load environment variables from parent directory .env
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE"
    return 1
fi

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Configuration
BACKUP_DIR=$BACKUP_DIR
DATE=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS="${KEEP_DAYS:-90}"  # Keep backups for 30 days by default

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"; exit 1; }

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting Matrix backup..."

# Backup Synapse data (config, keys, media)
log "Backing up Synapse data volume..."
docker run --rm \
    -v synapse_data:/data:ro \
    -v "$BACKUP_DIR":/backup \
    alpine \
    tar czf "/backup/synapse_data_${DATE}.tar.gz" -C /data . \
    || error "Failed to backup Synapse data"

log "Synapse data backed up: synapse_data_${DATE}.tar.gz"

# Backup PostgreSQL database
log "Backing up PostgreSQL database..."
docker compose exec -T db pg_dump -U synapse synapse | gzip > "$BACKUP_DIR/synapse_db_${DATE}.sql.gz" \
    || error "Failed to backup database"

log "Database backed up: synapse_db_${DATE}.sql.gz"

# Backup .env file
if [ -f .env ]; then
    log "Backing up .env file..."
    cp .env "$BACKUP_DIR/env_${DATE}.backup" \
        || warn "Failed to backup .env file"
    log "Environment backed up: env_${DATE}.backup"
fi

# Calculate sizes
SYNAPSE_SIZE=$(du -h "$BACKUP_DIR/synapse_data_${DATE}.tar.gz" | cut -f1)
DB_SIZE=$(du -h "$BACKUP_DIR/synapse_db_${DATE}.sql.gz" | cut -f1)

log "Backup sizes: Synapse=$SYNAPSE_SIZE, Database=$DB_SIZE"

# Clean old backups
log "Cleaning backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -name "synapse_data_*.tar.gz" -mtime +$KEEP_DAYS -delete
find "$BACKUP_DIR" -name "synapse_db_*.sql.gz" -mtime +$KEEP_DAYS -delete
find "$BACKUP_DIR" -name "env_*.backup" -mtime +$KEEP_DAYS -delete

BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/synapse_data_*.tar.gz 2>/dev/null | wc -l)
log "Backup complete! Total backups: $BACKUP_COUNT"
log "Backup location: $BACKUP_DIR"
