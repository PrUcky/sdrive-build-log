#!/usr/bin/env bash
# ==============================================================================
# sdrive-firewall.sh — Strict UFW Lockdown for Week 06
# ==============================================================================
# Enforces the final security perimeter.
#
# Rules:
# 1. Default DENY all incoming traffic.
# 2. Default ALLOW all outgoing traffic.
# 3. ALLOW SSH (port 22) ONLY on the physical LAN interface.
# 4. ALLOW all traffic ONLY on the tailscale0 interface.
#
# By applying this, even if Docker binds Caddy to 0.0.0.0:443, the host firewall
# will drop packets from the local LAN. The Tailnet becomes the ONLY way to reach
# the Caddy HTTPS proxy.
#
# Reference: weeks/week-06/day-39.md
# ==============================================================================
set -euo pipefail

echo "======================================================================"
echo " sdrive — Applying Strict UFW Rules"
echo "======================================================================"

# Determine primary physical interface (usually end0 or eth0 on ROCK 3C)
PHYS_IFACE=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")
echo "Detected physical interface: $PHYS_IFACE"

echo "Resetting UFW to default state..."
ufw --force reset

echo "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

echo "Allowing SSH on local LAN interface ($PHYS_IFACE)..."
ufw allow in on "$PHYS_IFACE" to any port 22 proto tcp

echo "Allowing Tailscale tunnel traffic (UDP 41641)..."
ufw allow 41641/udp

echo "Allowing all authenticated traffic on the tailnet (tailscale0)..."
ufw allow in on tailscale0

echo "Enabling UFW..."
ufw --force enable

echo "======================================================================"
echo "Firewall locked down."
ufw status verbose
