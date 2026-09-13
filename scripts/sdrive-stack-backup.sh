#!/usr/bin/env bash
# ==============================================================================
# sdrive-stack-backup.sh — Docker Volume Snapshot Backup
# ==============================================================================
# Creates timestamped tar.gz backups of all sdrive Docker volumes.
# Designed for scheduled cron execution or manual pre-upgrade snapshots.
#
# Usage:
#   ./scripts/sdrive-stack-backup.sh [backup-dir]
#   Default backup-dir: /mnt/data/backups
#
# Backup contents:
#   - postgres-data: Full PostgreSQL data directory
#   - garage-meta: Garage SQLite metadata (NOT the blob data)
#   - museum-data: Museum application data
#
# NOTE: garage-data (encrypted photo blobs) is NOT backed up by this script
# because it can be multi-gigabytes. Blob backup strategy is covered in Week 04.
#
# Restore: See docs/first-account-setup.md for re-initialization after restore.
# Reference: weeks/week-03/day-23.md
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${1:-/mnt/data/backups}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
COMPOSE_PROJECT="sdrive-stack"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Volumes to back up (metadata only — not the multi-GB blob store)
VOLUMES=(
    "${COMPOSE_PROJECT}_postgres-data"
    "${COMPOSE_PROJECT}_garage-meta"
    "${COMPOSE_PROJECT}_museum-data"
)

echo "======================================================================"
echo " sdrive — Volume Backup"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================================"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Check if stack is running
RUNNING=$(docker ps -q --filter "name=${COMPOSE_PROJECT}" | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} Stack is running. Backups are crash-consistent but not app-consistent."
    echo "       For app-consistent backups, stop the stack first: docker compose stop"
fi

BACKUP_SUBDIR="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "${BACKUP_SUBDIR}"

for vol in "${VOLUMES[@]}"; do
    BASENAME=$(echo "$vol" | sed "s/${COMPOSE_PROJECT}_//")
    ARCHIVE="${BACKUP_SUBDIR}/${BASENAME}.tar.gz"

    echo -e "\nBacking up: ${vol}"

    # Check if volume exists
    if ! docker volume inspect "$vol" &>/dev/null; then
        echo -e "${YELLOW}[SKIP]${NC} Volume '${vol}' does not exist."
        continue
    fi

    # Create backup using a temporary alpine container
    docker run --rm \
        -v "${vol}":/source:ro \
        -v "${BACKUP_SUBDIR}":/backup \
        alpine:3.20 \
        tar czf "/backup/${BASENAME}.tar.gz" -C /source .

    SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
    echo -e "${GREEN}[OK]${NC} ${ARCHIVE} (${SIZE})"
done

# Write manifest
cat > "${BACKUP_SUBDIR}/manifest.txt" << EOF
sdrive volume backup
timestamp: ${TIMESTAMP}
date: $(date --iso-8601=seconds)
host: $(hostname)
docker version: $(docker --version)
volumes:
EOF

for vol in "${VOLUMES[@]}"; do
    echo "  - ${vol}" >> "${BACKUP_SUBDIR}/manifest.txt"
done

# Retention: keep only the last 5 backups
BACKUP_COUNT=$(ls -d "${BACKUP_DIR}"/20* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 5 ]; then
    EXCESS=$((BACKUP_COUNT - 5))
    echo -e "\n${YELLOW}[CLEANUP]${NC} Removing ${EXCESS} old backup(s)..."
    ls -d "${BACKUP_DIR}"/20* | head -n "${EXCESS}" | xargs rm -rf
fi

TOTAL_SIZE=$(du -sh "${BACKUP_SUBDIR}" | cut -f1)
echo -e "\n======================================================================"
echo -e "${GREEN} Backup complete: ${BACKUP_SUBDIR} (${TOTAL_SIZE})${NC}"
echo "======================================================================"
