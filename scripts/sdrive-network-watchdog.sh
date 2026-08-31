#!/usr/bin/env bash
# ==============================================================================
# sdrive-network-watchdog.sh — Network Liveness & Self-Healing Daemon
# ==============================================================================
set -euo pipefail

POLL_INTERVAL=30
MAX_FAILURES=3
FAILURE_COUNT=0

log_msg() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [netwatch] $*"
}

check_connectivity() {
    local gateway
    gateway=$(ip route | grep default | awk '{print $3}' | head -n 1 || echo "")

    if [ -z "$gateway" ]; then
        return 1
    fi

    # Ping default gateway with 2s timeout
    if ping -c 2 -W 2 "$gateway" &>/dev/null; then
        return 0
    fi

    # Fallback ping to 1.1.1.1 if gateway blocks ICMP
    if ping -c 2 -W 2 "1.1.1.1" &>/dev/null; then
        return 0
    fi

    return 1
}

log_msg "Starting sdrive Network Self-Healing Watchdog (Poll: ${POLL_INTERVAL}s)..."

while true; do
    if check_connectivity; then
        if [ "$FAILURE_COUNT" -gt 0 ]; then
            log_msg "Network connectivity restored. Resetting failure counter."
            FAILURE_COUNT=0
        fi
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        log_msg "WARNING: Network check failed (${FAILURE_COUNT}/${MAX_FAILURES})"

        if [ "$FAILURE_COUNT" -ge "$MAX_FAILURES" ]; then
            log_msg "CRITICAL: Persistent connectivity loss detected. Initiating network stack recovery..."
            
            # Restart Ethernet interface
            if command -v systemctl &>/dev/null; then
                log_msg "Restarting networking & Tailscale services..."
                systemctl restart systemd-networkd 2>/dev/null || true
                systemctl restart tailscaled 2>/dev/null || true
            fi
            
            FAILURE_COUNT=0
            sleep 10
        fi
    fi

    sleep "$POLL_INTERVAL"
done
