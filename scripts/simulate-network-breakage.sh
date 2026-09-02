#!/usr/bin/env bash
# ==============================================================================
# simulate-network-breakage.sh — Deliberate Network Failure Lab for Week 02
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo $0 ...)${NC}"
    exit 1
fi

case "${1:-help}" in
    firewall-block)
        echo -e "${YELLOW}--> Injecting Breakage 1: Blocking S3 Port 3900 in UFW...${NC}"
        ufw insert 1 deny 3900/tcp comment 'LAB BREAKAGE: S3 blocked'
        echo -e "[ ${GREEN}APPLIED${NC} ] S3 port 3900 is now blocked. Diagnose with: curl -v http://127.0.0.1:3900 and tcpdump -i any port 3900"
        ;;
    bad-dns)
        echo -e "${YELLOW}--> Injecting Breakage 2: Blackholing DNS resolver in /etc/resolv.conf...${NC}"
        cp /etc/resolv.conf /etc/resolv.conf.lab-backup
        echo "nameserver 192.0.2.1" > /etc/resolv.conf # TEST-NET-1 unroutable IP
        echo -e "[ ${GREEN}APPLIED${NC} ] DNS pointing to invalid IP. Diagnose with: dig github.com and resolvectl status"
        ;;
    bad-mtu)
        echo -e "${YELLOW}--> Injecting Breakage 3: Reducing eth0 MTU to 600 bytes (fragmentation drop)...${NC}"
        ip link set dev eth0 mtu 600
        echo -e "[ ${GREEN}APPLIED${NC} ] eth0 MTU shrunk to 600. Large packets will fail. Diagnose with: ip link show eth0 and ping -M do -s 1400 1.1.1.1"
        ;;
    bad-gateway)
        echo -e "${YELLOW}--> Injecting Breakage 4: Corrupting Default Gateway Route...${NC}"
        CURRENT_GW=$(ip route | grep default | awk '{print $3}' | head -n 1 || echo "")
        echo "$CURRENT_GW" > /var/tmp/lab-original-gw.txt
        ip route del default
        ip route add default via 192.168.1.254 dev eth0 # Invalid gateway
        echo -e "[ ${GREEN}APPLIED${NC} ] Default gateway corrupted. Diagnose with: ip route show and traceroute 1.1.1.1"
        ;;
    restore)
        echo -e "${GREEN}--> Restoring all network settings to pristine baseline...${NC}"
        # 1. Reset UFW rule
        ufw delete deny 3900/tcp 2>/dev/null || true
        # 2. Restore DNS
        if [ -f /etc/resolv.conf.lab-backup ]; then
            mv /etc/resolv.conf.lab-backup /etc/resolv.conf
        fi
        # 3. Restore MTU
        ip link set dev eth0 mtu 1500
        # 4. Restore Gateway
        if [ -f /var/tmp/lab-original-gw.txt ]; then
            SAVED_GW=$(cat /var/tmp/lab-original-gw.txt)
            ip route del default 2>/dev/null || true
            ip route add default via "$SAVED_GW" dev eth0 2>/dev/null || true
            rm -f /var/tmp/lab-original-gw.txt
        fi
        systemctl restart systemd-resolved 2>/dev/null || true
        echo -e "[ ${GREEN}RESTORED${NC} ] All network interfaces, MTUs, DNS, and routes restored."
        ;;
    *)
        echo "Usage: sudo $0 [firewall-block | bad-dns | bad-mtu | bad-gateway | restore]"
        exit 1
        ;;
esac
