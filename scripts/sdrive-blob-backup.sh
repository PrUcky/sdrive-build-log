#!/usr/bin/env bash
# ==============================================================================
# sdrive-blob-backup.sh - Incremental Blob Backup via rsync
# ==============================================================================
# Incrementally synchronizes Garage's encrypted photo blobs to a backup
# destination using rsync.
#
# Usage:
#   ./scripts/sdrive-blob-backup.sh <destination>
#
# Reference: weeks/week-04/day-30.md
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DRY_RUN=""
DEST=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN="--dry-run" ;;
        *) DEST="$arg" ;;
    esac
done

if [ -z "$DEST" ]; then
    echo "Usage: $0 [--dry-run] <destination>"
    exit 1
fi

SOURCE="/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/"
NOTIFY_SCRIPT="$(dirname "$0")/sdrive-notify.sh"

if [ ! -d "$SOURCE" ]; then
    MSG="Source directory not found: $SOURCE"
    echo -e "${RED}[ERROR]${NC} $MSG"
    [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "CRITICAL" "Blob backup failed: $MSG"
    exit 1
fi

BWLIMIT="--bwlimit=50000"

echo "======================================================================"
echo " sdrive - Blob Backup (rsync incremental)"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================================"
echo "Source:      $SOURCE"
echo "Destination: $DEST"
[ -n "$DRY_RUN" ] && echo -e "${YELLOW}Mode: DRY RUN (no changes will be written)${NC}"

START_TIME=$(date +%s)
rsync -av --delete --stats --checksum $BWLIMIT $DRY_RUN "$SOURCE" "$DEST" 2>&1
RSYNC_EXIT=$?
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

echo ""
if [ $RSYNC_EXIT -eq 0 ]; then
    MSG="Blob backup completed in ${DURATION}s."
    echo -e "${GREEN}[OK]${NC} $MSG"
    [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "SUCCESS" "$MSG"
elif [ $RSYNC_EXIT -eq 24 ]; then
    MSG="Blob backup completed (exit 24, vanished files). Duration: ${DURATION}s."
    echo -e "${YELLOW}[WARN]${NC} $MSG"
    [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "WARN" "$MSG"
else
    MSG="rsync exited with code ${RSYNC_EXIT}. Duration: ${DURATION}s."
    echo -e "${RED}[ERROR]${NC} $MSG"
    [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "ERROR" "$MSG"
    exit $RSYNC_EXIT
fi
