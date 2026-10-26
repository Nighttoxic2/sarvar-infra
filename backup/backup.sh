#!/bin/bash
# 3-2-1 Backup Strategy for Sarvar
# 3 copies, 2 media types, 1 offsite
# Runs daily via cron: 0 2 * * * /path/to/backup.sh

set -euo pipefail

# ===== CONFIGURATION =====
DATE=$(date +%F-%H%M)
BACKUP_DIR="/mnt/Data/immich/backups"
RETENTION_LOCAL_DAYS=30
RETENTION_OFFSITE_DAYS=90
RCLONE_REMOTE="b2:immich-backups"  # Configure: rclone config

# ===== COLORS =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%F %T')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%F %T')] WARN:${NC} $*"; }
error() { echo -e "${RED}[$(date +'%F %T')] ERROR:${NC} $*"; }

# ===== PRE-CHECKS =====
if ! docker ps --format '{{.Names}}' | grep -q '^immich_postgres$'; then
    error "PostgreSQL container not running"
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    warn "rclone not installed - offsite backup skipped"
    RCLONE_AVAILABLE=false
else
    RCLONE_AVAILABLE=true
fi

# ===== BACKUP POSTGRESQL =====
log "Starting PostgreSQL dump..."
docker exec immich_postgres pg_dump -U postgres immich | gzip > "${BACKUP_DIR}/immich-${DATE}.sql.gz"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    error "pg_dump failed"
    exit 1
fi

BACKUP_SIZE=$(du -h "${BACKUP_DIR}/immich-${DATE}.sql.gz" | cut -f1)
log "Backup created: immich-${DATE}.sql.gz (${BACKUP_SIZE})"

# ===== VERIFY BACKUP =====
log "Verifying backup integrity..."
if ! gzip -t "${BACKUP_DIR}/immich-${DATE}.sql.gz"; then
    error "Backup verification failed - corrupt gzip"
    exit 1
fi
log "Backup verification passed"

# ===== LOCAL RETENTION =====
log "Applying local retention (${RETENTION_LOCAL_DAYS} days)..."
find "${BACKUP_DIR}" -name 'immich-*.sql.gz' -mtime +${RETENTION_LOCAL_DAYS} -delete

# ===== OFFSITE BACKUP =====
if [[ "${RCLONE_AVAILABLE}" == "true" ]]; then
    log "Syncing to offsite (${RCLONE_REMOTE})..."
    rclone copy "${BACKUP_DIR}/" "${RCLONE_REMOTE}/" \
        --progress \
        --retention ${RETENTION_OFFSITE_DAYS}d \
        --exclude "*.tmp" \
        --transfers 4 \
        --checkers 8

    if [[ $? -eq 0 ]]; then
        log "Offsite sync completed"
    else
        error "Offsite sync failed"
        exit 1
    fi
fi

# ===== BACKUP IMMICH UPLOADS (incremental) =====
if [[ "${RCLONE_AVAILABLE}" == "true" ]]; then
    log "Syncing uploads to offsite..."
    rclone sync /mnt/Data/immich/upload/ "${RCLONE_REMOTE}/uploads/" \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --exclude "thumbs/**" \
        --exclude "encoded-video/**"

    if [[ $? -eq 0 ]]; then
        log "Uploads sync completed"
    else
        warn "Uploads sync had errors (non-fatal)"
    fi
fi

log "Backup job completed successfully"
