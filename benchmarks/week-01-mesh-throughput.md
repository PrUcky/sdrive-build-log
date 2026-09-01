# Week 01 Benchmark Telemetry — Tailscale WireGuard Mesh Performance

**Date Captured:** 2026-09-01  
**Hardware Node:** Radxa ROCK 3C (`sdrive-node1`, Tailscale IP: `100.64.0.10`)  
**Overlay Driver:** Linux Kernel WireGuard (via `tailscale0`)  
**Workstation Client:** Laptop (`100.64.0.5`, Tailscale v1.72.0)  
**Mobile Client:** iPhone 15 Pro / Pixel 8 (5G Cellular, Tailscale iOS/Android)

---

## 1. Connection Path & Latency Matrix (`tailscale ping`)

| Network Scenario | Physical Path | Connection Type | WireGuard Endpoint | Latency (RTT) | Packet Loss |
|---|---|---|---|---|---|
| **Same LAN (Wi-Fi 6 -> Switch)** | `192.168.1.100` -> `192.168.1.150` | **Direct P2P UDP** | `192.168.1.150:41641` | **0.82 ms** | 0.0% |
| **Remote 5G Cellular (Jio / Airtel)** | Cellular Modem -> CGNAT -> Home Router | **Direct P2P UDP (STUN Hole Punch)** | `157.48.x.x:41641` | **28.4 ms** | 0.0% |
| **Strict Symmetric NAT Simulation** | Double NAT Firewall with random port translation | **DERP Relay (Bangalore Node)** | `derp-blr.tailscale.com` | **52.1 ms** | 0.0% |

**Key Observation:** In both LAN and 5G cellular scenarios, Tailscale successfully punched through Carrier-Grade NAT using STUN, achieving a **100% direct peer-to-peer UDP connection** without routing packets through external relay servers.

---

## 2. WireGuard Encrypted Throughput (`iperf3` over `tailscale0`)

Test command executed over the Tailscale IP interface:
```bash
iperf3 -c 100.64.0.10 -P 4 -t 30
```

### Direct LAN Encrypted Stream:
```text
[ ID] Interval           Transfer     Bitrate         Retr
[SUM]   0.00-30.00  sec  1.61 GBytes   462 Mbits/sec    0             sender
[SUM]   0.00-30.00  sec  1.61 GBytes   461 Mbits/sec                  receiver
```
- **Encrypted Throughput:** **462 Mbps** sustained.
- **Bare Ethernet Baseline:** 941 Mbps.
- **Encryption Overhead Factor:** ~51% drop compared to unencrypted raw Ethernet, which is standard for software-driven ChaCha20-Poly1305 symmetric crypto on quad Cortex-A55 cores without dedicated cryptographic coprocessor acceleration for WireGuard.
- **Sufficiency Evaluation:** At 462 Mbps (57.7 MB/s), the encrypted tunnel can ingest a 10MB photo in **173 milliseconds**, which is well beyond the real-world upload speed of any residential home broadband connection (typically 100–300 Mbps).

---

## 3. Resource Overhead During Encrypted Ingestion

Captured via `htop` and `sdrive-health-watchdog` during 460 Mbps `iperf3` encryption stream:

- **Tailscaled Memory Footprint:** **28.4 MB RSS**.
- **CPU Utilization:**
  - Core 0 (Kernel softirq / WireGuard encryption worker): 64%
  - Core 1: 8%
  - Core 2: 6%
  - Core 3: 5%
  - **Total System CPU Load:** **20.7%**.
- **SoC Temperature:** Rose from $36.4^\circ\text{C}$ to $41.8^\circ\text{C}$ ($\Delta T = +5.4^\circ\text{C}$).
- **Power Draw:** $2.85\text{ W}$ (well within the 5V/3A power budget).
