#!/usr/bin/env bash
# ==============================================================================
# sdrive-restore-metadata.sh - Disaster Recovery Restore Script
# ==============================================================================
# Restores Docker volumes (postgres-data, garage-meta, museum-data) from a
# specified backup directory created by sdrive-stack-backup.sh.
#
# Usage:
#   ./scripts/sdrive-restore-metadata.sh /mnt/data/backups/20261009-030000
# ==============================================================================
set -euo pipefail

BACKUP_SUBDIR="${1:-}"
COMPOSE_PROJECT="sdrive-stack"
VOL_ROOT="/mnt/data/docker/volumes"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$BACKUP_SUBDIR" ] || [ ! -d "$BACKUP_SUBDIR" ]; then
    echo -e "${RED}[ERROR]${NC} Invalid or missing backup directory."
    echo "Usage: $0 /path/to/backup/YYYYMMDD-HHMMSS"
    exit 1
fi

if [ ! -f "${BACKUP_SUBDIR}/manifest.txt" ]; then
    echo -e "${RED}[ERROR]${NC} manifest.txt not found in ${BACKUP_SUBDIR}."
    exit 1
fi

echo "======================================================================"
echo " sdrive - METADATA RESTORE DRILL"
echo "======================================================================"
echo -e "${YELLOW}WARNING: This will overwrite existing metadata volumes!${NC}"
echo "Backup to restore: ${BACKUP_SUBDIR}"
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "Stopping containers..."
docker stop sdrive-stack-caddy-1 sdrive-stack-museum-1 sdrive-stack-garage-1 sdrive-stack-postgres-1 2>/dev/null || true

VOLUMES=("postgres-data" "garage-meta" "museum-data")

for BASENAME in "${VOLUMES[@]}"; do
    ARCHIVE="${BACKUP_SUBDIR}/${BASENAME}.tar.gz"
    FULL_VOL="${COMPOSE_PROJECT}_${BASENAME}"
    VOL_PATH="${VOL_ROOT}/${FULL_VOL}/_data"

    if [ ! -f "$ARCHIVE" ]; then
        echo -e "${YELLOW}[SKIP]${NC} Backup archive not found: ${ARCHIVE}"
        continue
    fi

    echo "Restoring ${BASENAME}..."
    
    # Backup existing if it exists
    if [ -d "$VOL_PATH" ]; then
        mv "$VOL_PATH" "${VOL_PATH}.bak.$(date +%s)"
    fi

    mkdir -p "$VOL_PATH"
    tar -xzf "$ARCHIVE" -C "$VOL_PATH"
    echo -e "${GREEN}[OK]${NC} Restored ${BASENAME}"
done

echo "======================================================================"
echo -e "${GREEN}Restore complete.${NC}"
echo "Run 'docker compose up -d' to restart the stack."
