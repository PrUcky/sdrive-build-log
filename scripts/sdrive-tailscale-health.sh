#!/usr/bin/env bash
# ==============================================================================
# sdrive-tailscale-health.sh — Tailscale Connection Health Monitor
# ==============================================================================
# Checks Tailscale daemon status, tunnel health, peer connectivity, and
# connection path (direct vs DERP relay).
#
# Usage: ./scripts/sdrive-tailscale-health.sh
# Cron:  */15 * * * * /opt/sdrive/scripts/sdrive-tailscale-health.sh --quiet \
#          >> /var/log/sdrive/tailscale-health.log 2>&1
#
# Reference: weeks/week-05/day-32.md
# ==============================================================================
set -euo pipefail

QUIET="${1:-}"
EXIT_CODE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { [[ "$QUIET" != "--quiet" ]] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1; }
log_crit()  { echo -e "${RED}[CRIT]${NC} $1"; [[ $EXIT_CODE -lt 2 ]] && EXIT_CODE=2; }

echo "=== sdrive Tailscale Health === $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

# --- 1. Daemon Status ---
if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    log_crit "tailscaled daemon is not running"
    echo "=== Exit code: ${EXIT_CODE} ==="
    exit $EXIT_CODE
fi
log_info "tailscaled daemon: running (PID $(pgrep tailscaled || echo '?'))"

# --- 2. Backend State ---
TS_STATUS=$(tailscale status --json 2>/dev/null)
if [ -z "$TS_STATUS" ]; then
    log_crit "Cannot retrieve Tailscale status (not authenticated?)"
    echo "=== Exit code: ${EXIT_CODE} ==="
    exit $EXIT_CODE
fi

BACKEND_STATE=$(echo "$TS_STATUS" | grep -oP '"BackendState":"\K[^"]+' || echo "unknown")
if [ "$BACKEND_STATE" = "Running" ]; then
    log_info "Backend state: ${BACKEND_STATE}"
else
    log_crit "Backend state: ${BACKEND_STATE} (expected: Running)"
fi

# --- 3. Self Node Info ---
SELF_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
SELF_NAME=$(tailscale status --self --json 2>/dev/null | grep -oP '"HostName":"\K[^"]+' || echo "unknown")
log_info "Self: ${SELF_NAME} (${SELF_IP})"

# --- 4. Peer Count ---
PEER_COUNT=$(tailscale status 2>/dev/null | grep -c -v "^$" || echo 0)
PEER_COUNT=$((PEER_COUNT - 1))  # Subtract self
if [ "$PEER_COUNT" -gt 0 ]; then
    log_info "Peers: ${PEER_COUNT} device(s) on tailnet"
else
    log_warn "No peers found on tailnet"
fi

# --- 5. Peer Details ---
if [[ "$QUIET" != "--quiet" ]]; then
    echo -e "\n--- Peer Status ---"
    tailscale status 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q "direct"; then
            echo -e "  ${GREEN}●${NC} $line"
        elif echo "$line" | grep -q "relay"; then
            echo -e "  ${YELLOW}●${NC} $line"
        elif echo "$line" | grep -q "offline"; then
            echo -e "  ${RED}●${NC} $line"
        else
            echo "  $line"
        fi
    done
fi

# --- 6. Connection Health ---
NETCHECK=$(tailscale netcheck 2>/dev/null || echo "")
if [ -n "$NETCHECK" ]; then
    UDP_OK=$(echo "$NETCHECK" | grep -c "UDP" || echo 0)
    DERP_LATENCY=$(echo "$NETCHECK" | grep -oP 'preferred DERP: \K.*' || echo "unknown")
    IPV4=$(echo "$NETCHECK" | grep -oP 'IPv4: \K\w+' || echo "unknown")
    IPV6=$(echo "$NETCHECK" | grep -oP 'IPv6: \K\w+' || echo "unknown")
    MAPPING=$(echo "$NETCHECK" | grep -oP 'MappingVariesByDestIP: \K\w+' || echo "unknown")

    log_info "IPv4: ${IPV4}, IPv6: ${IPV6}"
    log_info "Preferred DERP: ${DERP_LATENCY}"

    if [ "$MAPPING" = "true" ]; then
        log_warn "NAT mapping varies by destination (hard NAT — may require DERP relay)"
    else
        log_info "NAT mapping: consistent (direct connections likely)"
    fi
fi

# --- 7. Tailscale Interface ---
if ip link show tailscale0 &>/dev/null; then
    TS_MTU=$(ip link show tailscale0 | grep -oP 'mtu \K[0-9]+' || echo "?")
    TS_STATE=$(ip link show tailscale0 | grep -oP 'state \K\w+' || echo "?")
    log_info "Interface tailscale0: state=${TS_STATE}, mtu=${TS_MTU}"
else
    log_warn "tailscale0 interface not found"
fi

# --- 8. Memory Usage ---
TS_MEM=$(ps -o rss= -p $(pgrep tailscaled 2>/dev/null) 2>/dev/null || echo 0)
TS_MEM_MB=$(( TS_MEM / 1024 ))
log_info "tailscaled memory: ${TS_MEM_MB} MB"

echo "=== Exit code: ${EXIT_CODE} ==="
exit $EXIT_CODE
