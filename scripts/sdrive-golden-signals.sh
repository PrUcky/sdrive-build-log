#!/usr/bin/env bash
# ==============================================================================
# sdrive-golden-signals.sh — Four Golden Signals Health Snapshot
# ==============================================================================
# Outputs a single-screen diagnostic covering the four SRE golden signals:
#   1. LATENCY  — DNS resolution time to primary resolver
#   2. TRAFFIC  — Network byte counters on eth0
#   3. ERRORS   — Interface error/drop counters
#   4. SATURATION — Memory, disk, CPU load, uptime
#
# Also appends the last 5 journal warnings for quick triage.
#
# Usage:   sdrive-golden-signals  (or ./scripts/sdrive-golden-signals.sh)
# Install: cp scripts/sdrive-golden-signals.sh /usr/local/bin/sdrive-golden-signals
#
# Reference: weeks/week-02/day-17.md
# ==============================================================================
set -euo pipefail

IFACE="${1:-eth0}"
DNS_TARGET="ente.io"
DNS_RESOLVER="1.1.1.1"

echo "========================================"
echo " sdrive — Golden Signals Snapshot"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================"

# --- LATENCY ---
echo -e "\n[LATENCY] DNS resolution to ${DNS_RESOLVER}:"
if command -v dig &>/dev/null; then
    dig @"${DNS_RESOLVER}" "${DNS_TARGET}" +stats 2>&1 | grep "Query time" || echo "  (dig query failed)"
else
    echo "  (dig not installed — apt install dnsutils)"
fi

# --- TRAFFIC ---
echo -e "\n[TRAFFIC] Network counters (${IFACE}):"
if [ -f "/sys/class/net/${IFACE}/statistics/rx_bytes" ]; then
    RX=$(cat "/sys/class/net/${IFACE}/statistics/rx_bytes")
    TX=$(cat "/sys/class/net/${IFACE}/statistics/tx_bytes")
    printf "  RX: %s MB  TX: %s MB\n" "$((RX / 1048576))" "$((TX / 1048576))"
else
    echo "  (interface ${IFACE} not found)"
fi

# --- ERRORS ---
echo -e "\n[ERRORS] Interface error counters:"
ip -s link show "${IFACE}" 2>/dev/null | grep -A 1 "RX errors" || echo "  (could not read counters)"

# --- SATURATION ---
echo -e "\n[SATURATION] Resource utilization:"

# Memory
MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
printf "  Memory: %s MB / %s MB (%s%%)\n" "$((MEM_USED / 1024))" "$((MEM_TOTAL / 1024))" "${MEM_PCT}"

# Disk
printf "  Disk:   %s\n" "$(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"

# Load
printf "  Load:   %s\n" "$(cut -d' ' -f1-3 /proc/loadavg)"

# Uptime
printf "  Uptime: %s\n" "$(uptime -p)"

# CPU temperature (Rockchip thermal zone)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP_RAW / 1000))
    printf "  CPU:    %s°C\n" "${TEMP_C}"
fi

# --- JOURNAL WARNINGS ---
echo -e "\n[JOURNAL] Last 5 errors/warnings (24h):"
journalctl -p warning --since "24 hours ago" --no-pager -q 2>/dev/null | tail -5 || echo "  (none)"

echo -e "\n========================================"
