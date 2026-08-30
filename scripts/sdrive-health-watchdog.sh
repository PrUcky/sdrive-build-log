#!/usr/bin/env bash
# ==============================================================================
# sdrive-health-watchdog.sh — Hardware Telemetry & Thermal Monitor Daemon
# Runs as a sandboxed systemd service on the Radxa ROCK 3C appliance
# ==============================================================================
set -euo pipefail

LOG_FILE="/var/log/sdrive-health.log"
POLL_INTERVAL=60

mkdir -p "$(dirname "$LOG_FILE")"

log_telemetry() {
    local timestamp temp_raw temp_c freq_khz freq_mhz mem_total mem_avail mem_used_pct disk_used_pct

    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Read SoC Thermal Zone 0 (millidegrees Celsius)
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$(awk "BEGIN {printf \"%.1f\", $temp_raw / 1000}")
    else
        temp_c="N/A"
    fi

    # Read CPU0 Current Frequency (kHz)
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" ]; then
        freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        freq_mhz=$((freq_khz / 1000))
    else
        freq_mhz="N/A"
    fi

    # Read Memory Statistics (MB)
    mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    mem_used_pct=$(( 100 - (mem_avail * 100 / mem_total) ))

    # Read Root Filesystem Usage (%)
    disk_used_pct=$(df / --output=pcent | tail -n 1 | tr -d ' %')

    # Format JSON log line
    local payload
    payload="{\"timestamp\":\"$timestamp\",\"soc_temp_c\":$temp_c,\"cpu_freq_mhz\":$freq_mhz,\"mem_used_pct\":$mem_used_pct,\"mem_avail_mb\":$mem_avail,\"disk_used_pct\":$disk_used_pct}"

    echo "$payload" | tee -a "$LOG_FILE"

    # Health Alerts
    if [ "$temp_c" != "N/A" ] && (( $(echo "$temp_c > 75.0" | bc -l) )); then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"WARN\",\"message\":\"High SoC Temperature: ${temp_c}C\"}" >&2
    fi

    if [ "$disk_used_pct" -ge 90 ]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"WARN\",\"message\":\"Root Storage Nearly Full: ${disk_used_pct}%\"}" >&2
    fi
}

echo "Starting sdrive Health Watchdog Daemon (Poll Interval: ${POLL_INTERVAL}s)..."
while true; do
    log_telemetry
    sleep "$POLL_INTERVAL"
done
