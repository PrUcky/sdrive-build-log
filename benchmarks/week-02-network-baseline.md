# Week 02 — Network Baseline Measurements

Baseline network telemetry captured during Week 02 (Networking) on the Radxa ROCK 3C running Armbian Bookworm. These measurements establish the known-good network performance profile against which future regressions (container overhead, WireGuard encryption, NVMe I/O contention) will be compared.

---

## Test Environment

| Parameter | Value |
|---|---|
| Board | Radxa ROCK 3C (RK3566, 4GB LPDDR4) |
| NIC | Realtek RTL8211F Gigabit Ethernet PHY |
| Uplink | Cat5e → TP-Link Gigabit Switch → ISP Router |
| ISP Topology | CGNAT (confirmed via `traceroute`: hop 2 = `100.64.0.1`) |
| OS | Armbian 24.8 Bookworm (kernel 6.1.x) |
| DNS Resolver | `systemd-resolved` with Cloudflare 1.1.1.1 primary |
| Date | September 4–6, 2026 |

---

## DNS Resolution Latency

Measured with `dig @<resolver> ente.io +stats` from the ROCK 3C, 5 samples averaged:

| Resolver | Provider | Latency (avg) | Protocol |
|---|---|---|---|
| `1.1.1.1` | Cloudflare | **8 ms** | UDP (opportunistic DoT) |
| `8.8.8.8` | Google | **12 ms** | UDP |
| `192.168.1.1` | Local Router | **14 ms** | UDP |
| `1.0.0.1` | Cloudflare Secondary | **9 ms** | UDP (opportunistic DoT) |
| `8.8.4.4` | Google Secondary | **13 ms** | UDP |

**Conclusion:** Cloudflare anycast PoP is physically closest to our ISP edge. Configured as primary resolver with Google as fallback.

---

## Traceroute Path Analysis

### Path to Cloudflare DNS (1.1.1.1)

```
Hop  Address          RTT (avg)
 1   192.168.1.1      0.85 ms    ← Home router
 2   100.64.0.1       4.15 ms    ← ISP CGNAT gateway (RFC 6598)
 3   * * *                       ← Silent backbone node
 4   172.16.48.1      8.37 ms    ← ISP peering edge
 5   72.14.209.1      9.03 ms    ← Google peering router
 6   1.1.1.1          8.15 ms    ← Cloudflare anycast
```

### Path to Google DNS (8.8.8.8)

```
Hop  Address          RTT (avg)
 1   192.168.1.1      0.83 ms
 2   100.64.0.1       4.22 ms
 3   * * *
 4   172.16.48.1      8.46 ms
 5   72.14.209.1      9.15 ms
 6   8.8.8.8          12.34 ms   ← +4ms vs Cloudflare
```

**Key observations:**
- CGNAT confirmed at hop 2 — port forwarding is impossible; Tailscale/WireGuard overlay is mandatory for remote access.
- Hops 1–5 are identical for both destinations — divergence occurs at the peering exchange.
- Hop 3 is an ICMP-silent ISP backbone router (common configuration).

---

## TCP Handshake Latency (LAN)

Measured with `tcpdump` during HTTP requests from desktop (`192.168.1.100`) to board (`192.168.1.150:8000`):

| Phase | Latency |
|---|---|
| SYN → SYN-ACK | **0.078 ms** |
| SYN-ACK → ACK | **0.812 ms** |
| Full 3-way handshake | **0.890 ms** |

**Conclusion:** Sub-millisecond TCP establishment on the LAN. The RTL8211F PHY introduces negligible latency. Container networking overhead (Week 03) will be measured against this baseline.

---

## Attack Surface Audit

Listening sockets as of Day 16 (pre-container deployment):

| Socket | Address | Port | Process | Exposure |
|---|---|---|---|---|
| TCP | `0.0.0.0` | 22 | `sshd` | LAN only (UFW rule #1) |
| TCP | `[::]` | 22 | `sshd` | Blocked (IPv6 UFW hardening) |
| UDP | `127.0.0.53` | 53 | `systemd-resolved` | Loopback only |

**Total exposed services:** 1 (SSH, key-auth only, LAN-scoped)

---

## Network Breakage Recovery

Tested during Day 14 chaos engineering session:

| Failure Mode | Detection Time | Recovery Time | Recovery Method |
|---|---|---|---|
| MTU crushed to 500 bytes | ~120 sec | ~165 sec | `sdrive-network-watchdog.service` cycled `eth0` |
| Default route deleted | Immediate (`Network is unreachable`) | Manual (`ip route add`) | Clean kernel error |
| DNS resolver poisoned | Immediate (wrong `dig` answer) | Manual (`resolvectl flush-caches`) | Cache flush + resolver failover |

---

## Comparison: Raw vs. Encrypted (Week 01 Reference)

| Metric | Raw Ethernet (Week 01) | WireGuard Overlay (Week 01) | Overhead |
|---|---|---|---|
| TCP throughput (`iperf3`) | 941 Mbps | 462 Mbps | 50.9% |
| Latency (LAN ping) | 0.35 ms | 0.89 ms | +154% |

*WireGuard encryption overhead is dominated by the RK3566's lack of hardware AES acceleration. The Cortex-A55 cores perform ChaCha20-Poly1305 in software.*

---

*Baseline established during Week 02 of the sdrive build log. All measurements taken on Armbian Bookworm, Radxa ROCK 3C, Realtek RTL8211F GbE, Cat5e cabling.*
