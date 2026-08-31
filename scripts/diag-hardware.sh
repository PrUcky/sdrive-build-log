#!/usr/bin/env bash
# ==============================================================================
# diag-hardware.sh — Hardware Health, Thermals, & Resource Inspector
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================================================"
echo " sdrive Hardware & System Resource Audit"
echo " Hostname: $(hostname) | Kernel: $(uname -r)"
echo "======================================================================"

# 1. Thermal & Clock Inspection
echo -e "\n--> 1. CPU & Thermal State:"
if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$(awk "BEGIN {printf \"%.1f\", $TEMP_RAW / 1000}")
    echo -e "SoC Temperature: ${GREEN}${TEMP_C}°C${NC}"
fi

if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" ]; then
    FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    FREQ_MHZ=$((FREQ_KHZ / 1000))
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    echo -e "CPU Frequency:   ${FREQ_MHZ} MHz (Governor: ${GOVERNOR})"
fi

# 2. Memory & ZRAM Breakdown
echo -e "\n--> 2. Memory & Swap Utilization:"
free -h

if command -v zramctl &>/dev/null; then
    echo -e "\n--> ZRAM Compression Pools:"
    zramctl || echo "No active zram pools"
fi

# 3. Storage & Block Devices
echo -e "\n--> 3. Block Device Topology & Mount Points:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL

echo -e "\n--> 4. Filesystem Capacity:"
df -h -x tmpfs -x devtmpfs

# 4. System Uptime & Load Averages
echo -e "\n--> 5. System Uptime & Load Averages:"
uptime

echo -e "\n======================================================================"
echo " Hardware Audit Complete."
echo "======================================================================"
