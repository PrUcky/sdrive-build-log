# Week 01 Retrospective — Linux, and the board wakes up

**Dates:** 2026-08-29 to 2026-09-03  
**Status:** COMPLETE (8/8 Milestones Delivered, 100% Exit Criteria Passed)  
**Total Engineering Hours:** ~37.5 Hours  

---

## 1. Executive Summary & Milestone Audit

Week 01 transitioned `sdrive` from an abstract architectural blueprint into a living, physical single-board computer operating headless on the desk. Every milestone in the master roadmap was completed, benchmarked, and codified into version control.

| Day | Milestone / Deliverable | Status | Key Metric / Verification |
|---|---|---|---|
| **Day 08** | **Hardware Bring-up & Serial Console** | **PASS** | CP2102 UART2 @ 1.5M baud connected; Armbian Linux 6.6 LTS booted headless. |
| **Day 09** | **Network Discovery & SSH Hardening** | **PASS** | `192.168.1.150` discovered; Ed25519 keys deployed; passwords disabled. |
| **Day 09** | **First Custom Systemd Watchdog** | **PASS** | `sdrive-health-watchdog.service` deployed with `ProtectSystem=strict`; survived reboot. |
| **Day 10** | **Thermal Stress & Line-Rate Benchmarks** | **PASS** | 15m `stress-ng` reached equilibrium at **54.2°C**; `iperf3` hit **941 Mbps TCP** line rate. |
| **Day 10** | **Automated Node Bootstrap & Flash Protection** | **PASS** | `scripts/bootstrap-node.sh` and 100MB journald cap (`01-sdrive-caps.conf`) codified. |
| **Day 11** | **Tailscale WireGuard Mesh & Remote Access** | **PASS** | Direct P2P 5G cellular SSH verified (`sdrive-node1.ts.net`); **462 Mbps** encrypted line rate. |
| **Day 12** | **Power-Pull Test (Ungraceful Shutdown)** | **PASS** | Yanked power at block #342; ext4 journal replayed in 3ms; **100% SHA-256 integrity match**. |
| **Day 12** | **24-Hour Soak Test Stability** | **PASS** | 24h continuous uptime; 0 kernel crashes; steady 182MB RAM; 0 MMC errors. |

---

## 2. Exit Criterion Verification

The master curriculum specifies five mandatory exit criteria for Week 01:

1. **Power-cycle the board and SSH in with no password:**
   - **Audit:** Tested multiple cold reboots and ungraceful power cuts. In every instance, the board initialized within 7.1 seconds, brought up networking, and accepted administrative logins strictly via public Ed25519 keys (`ssh sdrive-admin@192.168.1.150` and `ssh sdrive-admin@sdrive-node1.ts.net`).
2. **Navigate confidently & explain what lives in each top-level directory:**
   - **Audit:** Documented filesystem hierarchy in daily logs (`/etc` configuration, `/var/log` on in-memory `zram1`, `/sys/class/thermal` hardware registers, `/var/lib` persistent service state).
3. **Start, stop, and inspect a service you wrote yourself:**
   - **Audit:** Wrote, enabled, and managed `sdrive-health-watchdog.service` and `sdrive-network-watchdog.service` using `systemctl status`, `journalctl -u`, and `systemctl restart`.
4. **Thermal Stability without Fans:**
   - **Audit:** Under 100% CPU load across 4 cores, the passive aluminum heatsink maintained the SoC at $54.2^\circ\text{C}$ ($>30^\circ\text{C}$ below the $85^\circ\text{C}$ throttling threshold).
5. **Flash Durability Measures in Place:**
   - **Audit:** Deployed Armbian `zram` RAM disk logging, `01-sdrive-caps.conf` (100MB journal ceiling), `fstrim.timer` weekly discard, and consolidated dirty page writeback (`vm.dirty_background_ratio=5`).

---

## 3. Power, Energy, & Budget Tracking

| Component | Cost (USD) | Measured Power Draw | Operating Notes |
|---|---|---|---|
| **Radxa ROCK 3C (4GB LPDDR4)** | \$35.00 | **1.95 W (Idle)** | Rockchip RK3566 downclocked to 408MHz |
| **SanDisk Max Endurance 64GB** | \$18.50 | ~0.15 W | ext4 ordered mode, 43 MB/s sequential writes |
| **Aluminum Heatsink + 3M Tape** | \$2.90 | 0.00 W | Passive dissipation, 54.2°C at peak compute |
| **5V/3A USB-C Power Adapter** | \$8.50 | ~85% Efficiency | Regulated 5.10V output rail |
| **CP2102 USB-to-UART Adapter** | \$3.50 | ~0.05 W | Hardware debugging console @ 1.5M baud |
| **Total Hardware Cost** | **\$68.40** | **4.35 W (Max Peak)** | **Electricity Cost: ~\$0.35 / month (24/7)** |

---

## 4. Friction Log & Engineering Learnings

1. **Rockchip RK3566 UART Baud Rate:**
   - *Friction:* Initial serial console attempts at the industry-standard `115200` baud produced garbage ASCII characters.
   - *Resolution:* Discovered that Rockchip RK35xx boot ROM and U-Boot run at **1,500,000 baud** (1.5 Mbps). Configured `picocom -b 1500000 /dev/ttyUSB0` to capture clean hardware boot telemetry.
2. **TCP Receive Window Scaling on Linux 6.6:**
   - *Friction:* Initial single-stream `iperf3` tests stalled at ~720 Mbps on Gigabit Ethernet.
   - *Resolution:* Bumper `net.core.rmem_max` and `net.core.wmem_max` to 16MB in `99-sdrive-tuning.conf`, allowing the TCP congestion window to scale rapidly and achieve **941 Mbps**.
3. **WireGuard MTU Clamping over Cellular Networks:**
   - *Friction:* Large multi-megabyte photo uploads over mobile 5G risk Path MTU Discovery blackholes due to WireGuard's 80-byte encapsulation overhead.
   - *Resolution:* Tailscale's virtual `tailscale0` interface enforces MTU 1280 bytes with automatic TCP MSS clamping to 1240 bytes, guaranteeing zero packet fragmentation drops.

---

## 5. Week 02 Lookahead (Networking, properly)

In Week 02, we transition from host-level Linux administration to deep network engineering:
- Mapping the home subnet and building an interactive ASCII network topology.
- Serving HTTP endpoints on the LAN and accessing them from mobile browsers.
- Deep packet inspection using `tcpdump` and Wireshark.
- Executing our deliberate network breakage laboratory (`scripts/simulate-network-breakage.sh`) to diagnose port blocks, MTU drops, and DNS failures with tools rather than guesses.
