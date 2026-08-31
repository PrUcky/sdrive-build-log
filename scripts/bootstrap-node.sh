#!/usr/bin/env bash
# ==============================================================================
# bootstrap-node.sh — Idempotent System Hardening & Provisioning Script
# Target Node: Radxa ROCK 3C running Armbian Bookworm (Linux 6.6 LTS)
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo $0)${NC}"
    exit 1
fi

echo "======================================================================"
echo " sdrive Node Bootstrap & System Hardening"
echo " Node Hostname: $(hostname)"
echo " Kernel Version: $(uname -r)"
echo " Architecture:   $(uname -m)"
echo "======================================================================"

# 1. Update Package Index & Install Essential Diagnostics
echo -e "\n--> Step 1: Updating Package Repositories & Base Utilities..."
apt-get update -y
apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    htop \
    iotop \
    sysstat \
    fio \
    iperf3 \
    stress-ng \
    ufw \
    ca-certificates

# 2. Deploy Journald Flash Protection Caps
echo -e "\n--> Step 2: Configuring systemd-journald Log Caps (Flash Protection)..."
mkdir -p /etc/systemd/journald.conf.d
if [ -f "config/systemd/journald.conf.d/01-sdrive-caps.conf" ]; then
    cp config/systemd/journald.conf.d/01-sdrive-caps.conf /etc/systemd/journald.conf.d/
    systemctl restart systemd-journald
    echo -e "[ ${GREEN}OK${NC} ] journald caps applied (Max 100MB disk usage)"
fi

# 3. Kernel Sysctl Network & Memory Tuning
echo -e "\n--> Step 3: Applying Linux Kernel Sysctl Optimizations..."
cat <<'EOF' > /etc/sysctl.d/99-sdrive-tuning.conf
# sdrive Kernel & Network Buffer Tuning
# Increase TCP max buffer sizes for Gigabit saturation
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Increase socket listen backlog queue for concurrent client uploads
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

# Memory & Swap Behavior (Minimize unnecessary flash swap writes)
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl --system >/dev/null
echo -e "[ ${GREEN}OK${NC} ] Sysctl kernel optimizations loaded"

# 4. Deploy OpenSSH Hardening
echo -e "\n--> Step 4: Applying OpenSSH Server Hardening..."
if [ -f "config/ssh/01-sdrive-hardening.conf" ]; then
    cp config/ssh/01-sdrive-hardening.conf /etc/ssh/sshd_config.d/
    if sshd -t; then
        systemctl reload ssh
        echo -e "[ ${GREEN}OK${NC} ] OpenSSH hardened to Ed25519 keys only"
    else
        echo -e "[ ${RED}ERROR${NC} ] sshd configuration test failed! Reverting."
        rm -f /etc/ssh/sshd_config.d/01-sdrive-hardening.conf
    fi
fi

# 5. Configure Basic Firewall (UFW)
echo -e "\n--> Step 5: Configuring Host Firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH Administrative Port'
ufw allow in on tailscale0 comment 'Allow full traffic on Tailscale mesh'
# Enable UFW non-interactively
ufw --force enable
echo -e "[ ${GREEN}OK${NC} ] UFW active (SSH & Tailscale allowed)"

# 6. Deploy Health Watchdog Service
echo -e "\n--> Step 6: Deploying sdrive-health-watchdog service..."
if [ -f "scripts/sdrive-health-watchdog.sh" ] && [ -f "config/systemd/sdrive-health-watchdog.service" ]; then
    cp scripts/sdrive-health-watchdog.sh /usr/local/bin/
    chmod +x /usr/local/bin/sdrive-health-watchdog.sh
    cp config/systemd/sdrive-health-watchdog.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now sdrive-health-watchdog.service
    echo -e "[ ${GREEN}OK${NC} ] sdrive-health-watchdog active and enabled"
fi

echo -e "\n======================================================================"
echo -e "${GREEN}SUCCESS: sdrive Node Provisioning & Hardening Complete!${NC}"
echo "======================================================================"
