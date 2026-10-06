#!/usr/bin/env bash
# ==============================================================================
# sdrive-stack-backup.sh - Docker Volume Snapshot Backup
# ==============================================================================
# Creates timestamped tar.gz backups of all sdrive Docker volumes.
#
# Usage:
#   ./scripts/sdrive-stack-backup.sh [backup-dir]
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${1:-/mnt/data/backups}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
COMPOSE_PROJECT="sdrive-stack"
NOTIFY_SCRIPT="$(dirname "$0")/sdrive-notify.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VOLUMES=("${COMPOSE_PROJECT}_postgres-data" "${COMPOSE_PROJECT}_garage-meta" "${COMPOSE_PROJECT}_museum-data")

echo "======================================================================"
echo " sdrive - Volume Backup"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================================"

mkdir -p "${BACKUP_DIR}"
BACKUP_SUBDIR="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "${BACKUP_SUBDIR}"

for vol in "${VOLUMES[@]}"; do
    BASENAME=$(echo "$vol" | sed "s/${COMPOSE_PROJECT}_//")
    ARCHIVE="${BACKUP_SUBDIR}/${BASENAME}.tar.gz"

    if ! docker volume inspect "$vol" &>/dev/null; then
        echo -e "${YELLOW}[SKIP]${NC} Volume '${vol}' does not exist."
        continue
    fi

    if ! docker run --rm -v "${vol}":/source:ro -v "${BACKUP_SUBDIR}":/backup alpine:3.20 tar czf "/backup/${BASENAME}.tar.gz" -C /source . ; then
        MSG="Failed to tar volume ${vol}"
        echo -e "${RED}[ERROR]${NC} $MSG"
        [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "ERROR" "Metadata backup failed: $MSG"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} ${ARCHIVE}"
done

cat > "${BACKUP_SUBDIR}/manifest.txt" << EOF
sdrive volume backup
timestamp: ${TIMESTAMP}
date: $(date --iso-8601=seconds)
host: $(hostname)
volumes:
EOF
for vol in "${VOLUMES[@]}"; do echo "  - ${vol}" >> "${BACKUP_SUBDIR}/manifest.txt"; done

BACKUP_COUNT=$(ls -d "${BACKUP_DIR}"/20* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 5 ]; then
    EXCESS=$((BACKUP_COUNT - 5))
    ls -d "${BACKUP_DIR}"/20* | head -n "${EXCESS}" | xargs rm -rf
fi

TOTAL_SIZE=$(du -sh "${BACKUP_SUBDIR}" | cut -f1)
echo -e "${GREEN}Backup complete: ${BACKUP_SUBDIR} (${TOTAL_SIZE})${NC}"
[ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "SUCCESS" "Metadata backup complete (${TOTAL_SIZE})."
