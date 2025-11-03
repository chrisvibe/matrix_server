#!/bin/bash

# Matrix Server Restore Script

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

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"; exit 1; }

# Check if backup directory exists
[ -d "$BACKUP_DIR" ] || error "Backup directory not found: $BACKUP_DIR"

# List available backups
echo -e "${GREEN}Available backups:${NC}"
echo
ls -lh "$BACKUP_DIR"/synapse_data_*.tar.gz 2>/dev/null | awk '{print $9, "(" $5 ")"}'
echo

# Get backup date from user
if [ -z "$1" ]; then
    echo -n "Enter backup date to restore (YYYYMMDD_HHMMSS): "
    read BACKUP_DATE
else
    BACKUP_DATE="$1"
fi

# Verify backup files exist
SYNAPSE_BACKUP="$BACKUP_DIR/synapse_data_${BACKUP_DATE}.tar.gz"
DB_BACKUP="$BACKUP_DIR/synapse_db_${BACKUP_DATE}.sql.gz"
ENV_BACKUP="$BACKUP_DIR/env_${BACKUP_DATE}.backup"

[ -f "$SYNAPSE_BACKUP" ] || error "Synapse backup not found: $SYNAPSE_BACKUP"
[ -f "$DB_BACKUP" ] || error "Database backup not found: $DB_BACKUP"

# Warning
warn "⚠️  WARNING: This will REPLACE your current Matrix server data!"
warn "Make sure you have stopped the services first: docker compose down"
echo
echo -n "Continue with restore? (yes/no): "
read CONFIRM

[ "$CONFIRM" = "yes" ] || error "Restore cancelled"

# Stop services if running
log "Stopping services..."
docker compose down 2>/dev/null || true

# Restore Synapse data
log "Restoring Synapse data volume..."
docker run --rm \
    -v synapse_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine sh -c "rm -rf /data/* && tar xzf /backup/synapse_data_${BACKUP_DATE}.tar.gz -C /data" \
    || error "Failed to restore Synapse data"

log "Synapse data restored"

# Restore database
log "Restoring PostgreSQL database..."

# Start only the database
docker compose up -d db
log "Waiting for database to be ready..."
sleep 10

# Drop and recreate database
docker compose exec -T db psql -U synapse -d postgres -c "DROP DATABASE IF EXISTS synapse;" \
    || error "Failed to drop database"
docker compose exec -T db psql -U synapse -d postgres -c "CREATE DATABASE synapse OWNER synapse;" \
    || error "Failed to create database"

# Restore data
log "Restoring database (logging to restore_${BACKUP_DATE}.log)..."
gunzip -c "$DB_BACKUP" | docker compose exec -T db psql -U synapse -d synapse > "$BACKUP_DIR/restore_${BACKUP_DATE}.log" 2>&1 \
    || error "Failed to restore database"
log "Database restore complete. Check $BACKUP_DIR/restore_${BACKUP_DATE}.log for details."

log "Database restored"

# Restore .env if available
if [ -f "$ENV_BACKUP" ]; then
    warn "Environment backup found: $ENV_BACKUP"
    warn "Review and restore manually if needed"
fi

# Stop database
docker compose down

log "✅ Restore complete!"
log "Start services with: docker compose up -d"
