# Network Breakage Laboratory & Diagnostic Runbook

*Week 02 Preparation Reference Guide*

In Week 02, we do not learn networking from theoretical OSI layer diagrams. We learn networking by deliberately breaking the appliance's network stack and using standard Linux diagnostics (`ip`, `ss`, `dig`, `curl -v`, `ping`, `traceroute`, `tcpdump`) to identify the exact point of failure.

---

## 1. The Diagnostic Philosophy: Tools vs. Guessing

When an upload fails or an SSH session hangs, novice developers immediately begin randomly restarting services or editing configuration files. 

**The Rule:** You are not allowed to change a configuration file until you have proved what is broken using a diagnostic tool.

```
Diagnostic Hierarchy:
1. Physical / Interface State -> `ip link`, `ethtool`
2. IP Layer & Addressing      -> `ip -br addr`, `ip route`
3. Transport / Socket State   -> `ss -tulpn`, `ping`
4. Name Resolution            -> `dig`, `resolvectl status`
5. Application Layer          -> `curl -v`, `journalctl`
6. Packet-Level Reality       -> `tcpdump -nn -i any`
```

---

## 2. The Four Deliberate Breakages

### Breakage 1: Firewall Port Block (UFW)
- **Injection:** `sudo ./scripts/simulate-network-breakage.sh firewall-block`
- **Symptom:** Mobile app hangs for 30 seconds when uploading photos; `curl http://127.0.0.1:3900` times out.
- **Diagnostic Method:**
  ```bash
  # Check active firewall rules
  sudo ufw status verbose
  # Capture packet drops at kernel level
  sudo tcpdump -nn -i any port 3900
  ```
- **Root Cause Indicator:** SYN packets leave the client, but receive zero SYN-ACK or receive explicit TCP RST/ICMP admin prohibited.

### Breakage 2: Unroutable DNS Resolver
- **Injection:** `sudo ./scripts/simulate-network-breakage.sh bad-dns`
- **Symptom:** Board cannot update packages (`apt update` fails); Tailscale MagicDNS fails to resolve.
- **Diagnostic Method:**
  ```bash
  # Query DNS resolver directly
  dig @127.0.0.53 github.com
  cat /etc/resolv.conf
  ```
- **Root Cause Indicator:** `;; connection timed out; no servers could be reached`.

### Breakage 3: MTU Fragmentation Drop
- **Injection:** `sudo ./scripts/simulate-network-breakage.sh bad-mtu`
- **Symptom:** SSH and small pings work flawlessly, but `iperf3` or large 10MB photo uploads hang forever.
- **Diagnostic Method:**
  ```bash
  # Discover Path MTU using Don't Fragment (DF) bit
  ping -M do -s 1472 1.1.1.1 # Fails with Message too long
  ip link show eth0
  ```
- **Root Cause Indicator:** Interface MTU is lower than payload size with DF flag set.

### Breakage 4: Corrupted Default Gateway Route
- **Injection:** `sudo ./scripts/simulate-network-breakage.sh bad-gateway`
- **Symptom:** Local LAN communication works, but all WAN / internet access drops.
- **Diagnostic Method:**
  ```bash
  ip route show
  traceroute -n 1.1.1.1
  ```
- **Root Cause Indicator:** Default route points to non-existent or unroutable gateway IP.

---

## 3. Laboratory Restoration
To return the board to pristine operating condition at any time:
```bash
sudo ./scripts/simulate-network-breakage.sh restore
```
