#!/usr/bin/env bash
# ==============================================================================
# sdrive-container-health.sh — Docker Container Health Dashboard
# ==============================================================================
# Single-screen snapshot of all running containers: name, image, status,
# health, CPU/memory usage, restart count, and uptime.
#
# Usage: ./scripts/sdrive-container-health.sh
# Install: cp scripts/sdrive-container-health.sh /usr/local/bin/sdrive-container-health
#
# Reference: weeks/week-03/day-21.md
# ==============================================================================
set -euo pipefail

echo "========================================"
echo " sdrive — Container Health Dashboard"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================"

# Check if Docker is running
if ! docker info &>/dev/null; then
    echo "[ERROR] Docker daemon is not running."
    exit 1
fi

# Container count
RUNNING=$(docker ps -q | wc -l)
TOTAL=$(docker ps -aq | wc -l)
echo -e "\nContainers: ${RUNNING} running / ${TOTAL} total"

# Docker disk usage summary
echo -e "\n[DISK] Docker storage usage:"
docker system df --format 'table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || echo "  (unavailable)"

if [ "$RUNNING" -eq 0 ]; then
    echo -e "\nNo running containers."
    echo "========================================"
    exit 0
fi

# Per-container status
echo -e "\n[STATUS] Container health:"
printf "%-20s %-10s %-12s %-8s %s\n" "NAME" "STATE" "HEALTH" "RESTARTS" "UPTIME"
printf "%-20s %-10s %-12s %-8s %s\n" "----" "-----" "------" "--------" "------"

docker ps --format '{{.Names}}' | sort | while read -r name; do
    STATE=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
    HEALTH=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-check{{end}}' "$name" 2>/dev/null || echo "unknown")
    RESTARTS=$(docker inspect --format '{{.RestartCount}}' "$name" 2>/dev/null || echo "?")
    STARTED=$(docker inspect --format '{{.State.StartedAt}}' "$name" 2>/dev/null || echo "")

    # Calculate uptime
    if [ -n "$STARTED" ] && [ "$STARTED" != "" ]; then
        START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)
        if [ "$START_EPOCH" -gt 0 ]; then
            DIFF=$((NOW_EPOCH - START_EPOCH))
            HOURS=$((DIFF / 3600))
            MINS=$(( (DIFF % 3600) / 60 ))
            UPTIME="${HOURS}h ${MINS}m"
        else
            UPTIME="unknown"
        fi
    else
        UPTIME="unknown"
    fi

    printf "%-20s %-10s %-12s %-8s %s\n" "$name" "$STATE" "$HEALTH" "$RESTARTS" "$UPTIME"
done

# Resource usage
echo -e "\n[RESOURCES] CPU and memory per container:"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}' 2>/dev/null || echo "  (unavailable)"

# Recent container events
echo -e "\n[EVENTS] Last 10 container events:"
docker events --since "1h" --until "$(date --iso-8601=seconds)" --filter 'type=container' 2>/dev/null | tail -10 || echo "  (none in last hour)"

echo -e "\n========================================"
