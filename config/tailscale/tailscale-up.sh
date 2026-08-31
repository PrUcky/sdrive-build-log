#!/usr/bin/env bash
# ==============================================================================
# tailscale-up.sh — Tailscale Mesh Overlay Provisioning Script
# Target Path: /usr/local/bin/tailscale-up.sh
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo $0)${NC}"
    exit 1
fi

echo "======================================================================"
echo " sdrive Tailscale WireGuard Mesh Provisioning"
echo "======================================================================"

# 1. Install Tailscale Repository & Daemon if Missing
if ! command -v tailscale &>/dev/null; then
    echo -e "\n--> Installing Tailscale official repository..."
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    apt-get update -y
    apt-get install -y tailscale
    systemctl enable --now tailscaled
    echo -e "[ ${GREEN}OK${NC} ] Tailscale daemon installed and active"
fi

# 2. Authenticate & Connect Node
HOSTNAME="sdrive-node1"
echo -e "\n--> Bringing up Tailscale node with hostname: $HOSTNAME..."

tailscale up \
    --hostname="$HOSTNAME" \
    --accept-dns=true \
    --ssh=false \
    --reset

# 3. Retrieve Node Addresses
TAILSCALE_IP4=$(tailscale ip -4 || echo "N/A")
TAILSCALE_IP6=$(tailscale ip -6 || echo "N/A")

echo -e "\n======================================================================"
echo -e "${GREEN}Tailscale Mesh Connected Successfully!${NC}"
echo "IPv4 Address:  $TAILSCALE_IP4"
echo "IPv6 Address:  $TAILSCALE_IP6"
echo "MagicDNS Name: ${HOSTNAME}.your-tailnet.ts.net"
echo "======================================================================"

# 4. Check Connection Status
tailscale status
