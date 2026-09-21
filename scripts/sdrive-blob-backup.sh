#!/usr/bin/env bash
# ==============================================================================
# sdrive-blob-backup.sh — Incremental Blob Backup via rsync
# ==============================================================================
# Incrementally synchronizes Garage's encrypted photo blobs to a backup
# destination using rsync. Unlike sdrive-stack-backup.sh (which handles
# metadata volumes), this script handles the multi-gigabyte data tier.
#
# Features:
#   - Incremental: only new/changed blocks are transferred
#   - Bandwidth-limited: won't saturate the network during active use
#   - Dry-run mode: preview what would be synced without writing
#   - Integrity verified: rsync checksums every transferred block
#   - Deletion mirroring: backup reflects user-initiated deletions
#
# Usage:
#   ./scripts/sdrive-blob-backup.sh <destination>
#   ./scripts/sdrive-blob-backup.sh --dry-run <destination>
#
# Examples:
#   ./scripts/sdrive-blob-backup.sh /mnt/backup-drive/garage-data/
#   ./scripts/sdrive-blob-backup.sh user@nas:/backups/sdrive-blobs/
#   ./scripts/sdrive-blob-backup.sh --dry-run /mnt/usb-backup/
#
# Cron (nightly, after metadata backup):
#   30 3 * * * /opt/sdrive/scripts/sdrive-blob-backup.sh /mnt/backup/blobs/ \
#             >> /var/log/sdrive/blob-backup.log 2>&1
#
# Reference: weeks/week-04/day-30.md
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
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
    echo "  destination: local path or remote rsync target (user@host:/path/)"
    exit 1
fi

# Source: Garage data volume
SOURCE="/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/"

if [ ! -d "$SOURCE" ]; then
    echo -e "${RED}[ERROR]${NC} Source directory not found: $SOURCE"
    echo "Is the Garage container running? Check: docker compose ps"
    exit 1
fi

# Bandwidth limit: 50 MB/s to avoid saturating USB 3.0 bus during active use
# Remove --bwlimit for maximum speed during initial sync
BWLIMIT="--bwlimit=50000"

echo "======================================================================"
echo " sdrive — Blob Backup (rsync incremental)"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================================"
echo "Source:      $SOURCE"
echo "Destination: $DEST"
[ -n "$DRY_RUN" ] && echo -e "${YELLOW}Mode: DRY RUN (no changes will be written)${NC}"
echo ""

# Pre-sync: capture source size
SOURCE_SIZE=$(du -sh "$SOURCE" 2>/dev/null | cut -f1)
SOURCE_FILES=$(find "$SOURCE" -type f 2>/dev/null | wc -l)
echo "Source: ${SOURCE_SIZE} across ${SOURCE_FILES} block files"

# Run rsync
# Flags:
#   -a         : archive mode (preserves permissions, timestamps, symlinks)
#   -v         : verbose (list transferred files)
#   --delete   : remove files from dest that no longer exist in source
#   --progress : show per-file transfer progress
#   --stats    : show transfer summary statistics
#   --checksum : verify integrity of transferred blocks (slower but safer)
START_TIME=$(date +%s)

rsync -av \
    --delete \
    --progress \
    --stats \
    --checksum \
    $BWLIMIT \
    $DRY_RUN \
    "$SOURCE" \
    "$DEST" 2>&1

RSYNC_EXIT=$?
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

echo ""
if [ $RSYNC_EXIT -eq 0 ]; then
    echo -e "${GREEN}[OK]${NC} Blob backup completed in ${DURATION} seconds."
elif [ $RSYNC_EXIT -eq 24 ]; then
    # Exit 24 = "some files vanished before they could be transferred"
    # This is expected when Garage is actively writing during backup
    echo -e "${YELLOW}[WARN]${NC} Blob backup completed with vanished files (exit 24). This is"
    echo "       normal if the stack is actively receiving uploads during backup."
    echo "       Duration: ${DURATION} seconds."
else
    echo -e "${RED}[ERROR]${NC} rsync exited with code ${RSYNC_EXIT}. Check output above."
    exit $RSYNC_EXIT
fi

# Post-sync: capture destination size
if [ -z "$DRY_RUN" ] && [ -d "$DEST" ]; then
    DEST_SIZE=$(du -sh "$DEST" 2>/dev/null | cut -f1)
    DEST_FILES=$(find "$DEST" -type f 2>/dev/null | wc -l)
    echo "Destination: ${DEST_SIZE} across ${DEST_FILES} block files"
fi

echo "======================================================================"
