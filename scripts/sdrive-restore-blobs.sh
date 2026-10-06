#!/usr/bin/env bash
# ==============================================================================
# sdrive-restore-blobs.sh - Disaster Recovery Blob Restore
# ==============================================================================
# Reverses the rsync direction to pull the multi-gigabyte blob archive from
# the backup destination back to the Garage data volume on the SSD.
#
# Usage:
#   ./scripts/sdrive-restore-blobs.sh /mnt/backup/blobs/
# ==============================================================================
set -euo pipefail

BACKUP_SRC="${1:-}"
DEST="/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$BACKUP_SRC" ]; then
    echo -e "${RED}[ERROR]${NC} Missing backup source path."
    echo "Usage: $0 /mnt/backup/blobs/"
    exit 1
fi

echo "======================================================================"
echo " sdrive - BLOB RESTORE DRILL"
echo "======================================================================"
echo "Source:      $BACKUP_SRC"
echo "Destination: $DEST"
echo -e "${YELLOW}WARNING: This will overwrite files in the destination!${NC}"
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "Ensuring Garage container is stopped to prevent corruption..."
docker stop sdrive-stack-garage-1 2>/dev/null || true
mkdir -p "$DEST"

START_TIME=$(date +%s)
rsync -av --progress --stats "$BACKUP_SRC" "$DEST"
RSYNC_EXIT=$?
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

if [ $RSYNC_EXIT -eq 0 ]; then
    echo -e "\n${GREEN}[OK]${NC} Blob restore completed in ${DURATION} seconds."
    echo "Run 'docker compose up -d' to restart Garage."
else
    echo -e "\n${RED}[ERROR]${NC} rsync exited with code ${RSYNC_EXIT}."
    exit $RSYNC_EXIT
fi
