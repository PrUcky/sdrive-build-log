#!/usr/bin/env bash
# ==============================================================================
# diag-network.sh — Comprehensive Network Diagnostic & Connectivity Inspector
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================================================"
echo " sdrive Network Diagnostic & Connectivity Audit"
echo " Date: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "======================================================================"

# 1. Interface & IP Addresses
echo -e "\n--> 1. Active Network Interfaces & IP Addresses:"
ip -br addr show

# 2. Kernel Routing Table
echo -e "\n--> 2. Kernel Routing Table & Default Gateway:"
ip route show

# 3. Default Gateway Reachability (Ping)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1 || echo "")
if [ -n "$GATEWAY" ]; then
    echo -e "\n--> 3. Pinging Default Gateway ($GATEWAY)..."
    if ping -c 3 -W 2 "$GATEWAY" &>/dev/null; then
        echo -e "[ ${GREEN}REACHABLE${NC} ] Gateway $GATEWAY responded to ICMP"
    else
        echo -e "[ ${RED}UNREACHABLE${NC} ] Gateway $GATEWAY failed to respond"
    fi
fi

# 4. DNS Resolution & Latency
echo -e "\n--> 4. Testing DNS Resolution (1.1.1.1 & github.com)..."
for target in "one.one.one.one" "github.com"; do
    START_TIME=$(date +%s%N)
    if getent hosts "$target" &>/dev/null; then
        END_TIME=$(date +%s%N)
        LATENCY=$(( (END_TIME - START_TIME) / 1000000 ))
        IP=$(getent hosts "$target" | awk '{print $1}' | head -n 1)
        echo -e "[ ${GREEN}RESOLVED${NC} ] $target -> $IP (${LATENCY}ms)"
    else
        echo -e "[ ${RED}FAILED${NC} ] Unable to resolve $target"
    fi
done

# 5. Active Listening Sockets
echo -e "\n--> 5. Active Listening Ports (TCP/UDP):"
ss -tulpn | grep LISTEN || echo "No active listening TCP sockets"

# 6. UFW Firewall State
echo -e "\n--> 6. UFW Firewall Status:"
if command -v ufw &>/dev/null; then
    ufw status verbose
else
    echo "ufw not installed"
fi

echo -e "\n======================================================================"
echo " Network Diagnostic Complete."
echo "======================================================================"
