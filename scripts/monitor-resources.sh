#!/usr/bin/env bash
# ==============================================================================
# monitor-resources.sh — Real-time Process, Memory, & I/O Telemetry Dashboard
# ==============================================================================
set -euo pipefail

clear
echo "======================================================================"
echo " sdrive Real-Time Resource & Process Telemetry Dashboard"
echo " Hostname: $(hostname) | Date: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "======================================================================"

# 1. System Load & Uptime
echo -e "\n--> 1. System Uptime & 1/5/15m Load Averages:"
uptime

# 2. CPU Core Frequencies & Thermal Zone
echo -e "\n--> 2. CPU Core Frequencies & Thermals:"
if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    TEMP_C=$(awk "BEGIN {printf \"%.1f\", $(cat /sys/class/thermal/thermal_zone0/temp) / 1000}")
    echo "SoC Temperature: ${TEMP_C}°C"
fi

for cpu in /sys/devices/system/cpu/cpu[0-3]; do
    cpu_name=$(basename "$cpu")
    if [ -f "$cpu/cpufreq/scaling_cur_freq" ]; then
        freq_mhz=$(( $(cat "$cpu/cpufreq/scaling_cur_freq") / 1000 ))
        governor=$(cat "$cpu/cpufreq/scaling_governor")
        echo "$cpu_name: ${freq_mhz} MHz (Governor: $governor)"
    fi
done

# 3. Memory & ZRAM Breakdown
echo -e "\n--> 3. Detailed Memory Distribution:"
free -h -w

if command -v zramctl &>/dev/null; then
    echo -e "\n--> ZRAM Compression Status:"
    zramctl
fi

# 4. Process Footprint of sdrive Core Daemons
echo -e "\n--> 4. sdrive Core Service Footprint (RSS, CPU%, Threads):"
printf "%-18s %-8s %-10s %-10s %-8s %-8s\n" "PROCESS" "PID" "USER" "RSS (MB)" "CPU %" "THREADS"
echo "----------------------------------------------------------------------"

for proc in "garage" "museum" "postgres" "tailscaled" "sshd" "systemd-journal"; do
    pgrep -f "$proc" 2>/dev/null | head -n 3 | while read -r pid; do
        if [ -d "/proc/$pid" ]; then
            pname=$(ps -p "$pid" -o comm= || echo "$proc")
            puser=$(ps -p "$pid" -o user= || echo "unknown")
            rss_kb=$(ps -p "$pid" -o rss= || echo "0")
            rss_mb=$(awk "BEGIN {printf \"%.1f\", $rss_kb / 1024}")
            cpu_pct=$(ps -p "$pid" -o %cpu= || echo "0.0")
            threads=$(ps -p "$pid" -o nlwp= || echo "1")
            printf "%-18s %-8s %-10s %-10s %-8s %-8s\n" "$pname" "$pid" "$puser" "$rss_mb" "$cpu_pct" "$threads"
        fi
    done
done

# 5. Disk I/O Statistics
echo -e "\n--> 5. Storage I/O Activity (/proc/diskstats):"
if command -v iostat &>/dev/null; then
    iostat -xz 1 1 | tail -n +4
else
    df -h -x tmpfs -x devtmpfs
fi

echo -e "\n======================================================================"
echo " Telemetry Snapshot Complete."
echo "======================================================================"
