#!/usr/bin/env bash
# ==============================================================================
# sdrive-storage-monitor.sh — Filesystem Health & Capacity Monitor
# ==============================================================================
# Designed for cron execution. Checks:
#   1. SSD capacity against warning/critical/fatal thresholds
#   2. Inode usage (ext4 can run out of inodes before disk space)
#   3. SMART health indicators (reallocated sectors, pending sectors)
#   4. Garage object count and data size
#   5. PostgreSQL database size
#   6. Docker volume sizes
#
# Exit codes:
#   0 = all clear
#   1 = warning threshold crossed
#   2 = critical threshold crossed
#   3 = fatal / immediate action required
#
# Usage:
#   ./scripts/sdrive-storage-monitor.sh          # Full report
#   ./scripts/sdrive-storage-monitor.sh --quiet   # Only warnings/errors
#
# Cron: 0 */6 * * * /opt/sdrive/scripts/sdrive-storage-monitor.sh --quiet \
#         >> /var/log/sdrive-storage-monitor.log 2>&1
#
# Reference: weeks/week-04/day-29.md
# ==============================================================================
set -euo pipefail

QUIET="${1:-}"
DISK_WARN=70
DISK_CRIT=85
DISK_FATAL=95
INODE_WARN=70
INODE_CRIT=85
EXIT_CODE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { [[ "$QUIET" != "--quiet" ]] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1; }
log_crit()  { echo -e "${RED}[CRIT]${NC} $1"; [[ $EXIT_CODE -lt 2 ]] && EXIT_CODE=2; }
log_fatal() { echo -e "${RED}[FATAL]${NC} $1"; EXIT_CODE=3; }

echo "=== sdrive Storage Monitor === $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

# --- 1. SSD Capacity ---
if mountpoint -q /mnt/data 2>/dev/null; then
    DISK_PCT=$(df /mnt/data --output=pcent | tail -1 | tr -d ' %')
    DISK_USED=$(df -h /mnt/data --output=used | tail -1 | tr -d ' ')
    DISK_AVAIL=$(df -h /mnt/data --output=avail | tail -1 | tr -d ' ')

    if [ "$DISK_PCT" -ge "$DISK_FATAL" ]; then
        log_fatal "SSD capacity at ${DISK_PCT}% (${DISK_USED} used, ${DISK_AVAIL} free) — RISK OF CORRUPTION"
    elif [ "$DISK_PCT" -ge "$DISK_CRIT" ]; then
        log_crit "SSD capacity at ${DISK_PCT}% (${DISK_USED} used, ${DISK_AVAIL} free) — stop non-essential writes"
    elif [ "$DISK_PCT" -ge "$DISK_WARN" ]; then
        log_warn "SSD capacity at ${DISK_PCT}% (${DISK_USED} used, ${DISK_AVAIL} free) — plan expansion"
    else
        log_info "SSD capacity: ${DISK_PCT}% (${DISK_USED} used, ${DISK_AVAIL} free)"
    fi

    # Inode check
    INODE_PCT=$(df -i /mnt/data --output=ipcent | tail -1 | tr -d ' %')
    if [ "$INODE_PCT" -ge "$INODE_CRIT" ]; then
        log_crit "Inode usage at ${INODE_PCT}% — too many small files"
    elif [ "$INODE_PCT" -ge "$INODE_WARN" ]; then
        log_warn "Inode usage at ${INODE_PCT}%"
    else
        log_info "Inode usage: ${INODE_PCT}%"
    fi
else
    log_fatal "/mnt/data is not mounted!"
fi

# --- 2. SMART Health ---
if command -v smartctl &>/dev/null && [ -b /dev/sda ]; then
    SMART_STATUS=$(smartctl -H /dev/sda 2>/dev/null | grep -i "result" | awk '{print $NF}' || echo "unknown")
    REALLOC=$(smartctl -A /dev/sda 2>/dev/null | grep "Reallocated_Sector" | awk '{print $NF}' || echo "?")
    PENDING=$(smartctl -A /dev/sda 2>/dev/null | grep "Current_Pending" | awk '{print $NF}' || echo "?")

    if [ "$SMART_STATUS" = "PASSED" ] && [ "$REALLOC" = "0" ]; then
        log_info "SMART: ${SMART_STATUS}, reallocated=${REALLOC}, pending=${PENDING}"
    else
        log_crit "SMART: ${SMART_STATUS}, reallocated=${REALLOC}, pending=${PENDING} — SSD degradation detected"
    fi
else
    log_info "SMART: smartctl not available or /dev/sda not found"
fi

# --- 3. Garage Stats ---
if docker ps -q --filter name=garage &>/dev/null; then
    GARAGE_INFO=$(docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen 2>/dev/null || echo "unavailable")
    if echo "$GARAGE_INFO" | grep -q "Size"; then
        GARAGE_SIZE=$(echo "$GARAGE_INFO" | grep "Size" | awk '{print $2, $3}')
        GARAGE_OBJS=$(echo "$GARAGE_INFO" | grep -oP '\(\K[0-9]+' || echo "?")
        log_info "Garage: ${GARAGE_SIZE} (${GARAGE_OBJS} objects)"
    else
        log_warn "Garage: could not read bucket info"
    fi
fi

# --- 4. PostgreSQL Size ---
if docker ps -q --filter name=postgres &>/dev/null; then
    PG_SIZE=$(docker exec sdrive-stack-postgres-1 \
      psql -U pguser -d ente_db -t -c "SELECT pg_size_pretty(pg_database_size('ente_db'));" 2>/dev/null | tr -d ' ' || echo "unavailable")
    log_info "PostgreSQL: ${PG_SIZE}"
fi

# --- 5. Docker Volume Sizes ---
if [[ "$QUIET" != "--quiet" ]]; then
    echo -e "\n--- Docker Volume Usage ---"
    for vol in postgres-data garage-meta garage-data museum-data; do
        VOL_PATH="/mnt/data/docker/volumes/sdrive-stack_${vol}/_data"
        if [ -d "$VOL_PATH" ]; then
            VOL_SIZE=$(du -sh "$VOL_PATH" 2>/dev/null | cut -f1)
            echo "  ${vol}: ${VOL_SIZE}"
        fi
    done
fi

# --- 6. Backup Freshness ---
BACKUP_DIR="/mnt/data/backups"
if [ -d "$BACKUP_DIR" ]; then
    LATEST=$(ls -d "${BACKUP_DIR}"/20* 2>/dev/null | tail -1 || echo "")
    if [ -n "$LATEST" ]; then
        BACKUP_AGE_HOURS=$(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 3600 ))
        if [ "$BACKUP_AGE_HOURS" -gt 48 ]; then
            log_warn "Latest backup is ${BACKUP_AGE_HOURS} hours old (${LATEST})"
        else
            log_info "Latest backup: ${BACKUP_AGE_HOURS}h ago (${LATEST})"
        fi
    else
        log_warn "No backups found in ${BACKUP_DIR}"
    fi
else
    log_warn "Backup directory ${BACKUP_DIR} does not exist"
fi

echo "=== Exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
