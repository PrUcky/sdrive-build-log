# Day 13 — Week 01 Retrospective and Reflection

**Week:** 01 · **Date:** 2026-09-03 · **Hours:** ~7.0

Today marks the formal conclusion of **Week 01 — Linux, and the board wakes up**. Seven days ago, `sdrive` was an abstract collection of architecture diagrams, mathematical proofs, and security threat models living on my laptop. Today, it is a physical, living single-board computer sitting on my desk—running hardened Linux 6.6 LTS, administering over an encrypted WireGuard mesh from 5G cellular, protected against flash wear, and proven to survive sudden power cuts with zero filesystem corruption.

## What I actually did

I dedicated today’s session to synthesizing our hardware bring-up phase: auditing our milestones, writing the formal Week 01 Retrospective, and drafting our second full-length technical essay.

### 1. The Week 01 Milestone Audit
I walked through every technical milestone defined in the master roadmap for Week 01:
1. **Cooling & Thermals (Day 08):** Mounted the anodized aluminum heatsink with 3M 8810 thermal tape. Verified steady-state thermal equilibrium at **54.2°C** under 100% CPU load (leaving $>30^\circ\text{C}$ of headroom below throttling).
2. **Serial Hardware Console (Day 08):** Connected the CP2102 USB-to-UART bridge to UART2 (Pins 6, 8, 10), discovered Rockchip’s high-speed **1,500,000 baud** rate, and captured the raw U-Boot SPL and Linux kernel bootstrap log.
3. **Headless Linux OS (Day 08):** Flashed Armbian Bookworm Linux 6.6 LTS to our SanDisk Max Endurance 64GB microSD card and achieved clean headless boot.
4. **Network Discovery & SSH Hardening (Day 09):** Located the board at `192.168.1.150`, deployed Ed25519 administrative keys, and locked down OpenSSH to disable password authentication and restrict ciphers to ChaCha20-Poly1305 and AES-256-GCM.
5. **Custom Systemd Watchdog (Day 09):** Wrote and deployed `sdrive-health-watchdog.service` with strict sandboxing (`ProtectSystem=strict`, 64MB RAM cap), verifying auto-restart and survival across reboots.
6. **Hardware & Network Saturation (Day 10):** Saturated raw Gigabit Ethernet with `iperf3` at **941 Mbps TCP** with zero packet retransmissions, while measuring power consumption at **1.95W idle** and **4.35W maximum stress**.
7. **Encrypted WireGuard Mesh (Day 11):** Deployed Tailscale on the board (`sdrive-node1`), verified direct P2P NAT hole-punching over 5G cellular SSH, and benchmarked encrypted throughput at **462 Mbps**.
8. **Power-Pull & Soak Test (Day 12):** Executed the dreaded ungraceful power-pull test during active I/O writes, verifying clean ext4 journal recovery in 3ms and **100% SHA-256 block integrity** across 341MB of test data, followed by a flawless 24-hour soak test.

### 2. Formulating the Week 01 Retrospective (`weeks/week-01/retro.md`)
I codified these results into our formal retrospective document at `weeks/week-01/retro.md`. 

The retrospective audits our budget (total hardware spend remaining at \$68.40 and power consumption translating to roughly \$0.35/month in electricity), details the friction encountered (UART baud rate mismatches, TCP receive window scaling, WireGuard MTU clamping), and verifies that all exit criteria for Week 01 have been met with zero compromises.

### 3. Authoring Technical Article 2
I wrote our second long-form public technical essay: `content/articles/week-01-the-board-wakes-up.md` (*The Board Wakes Up: Bring-up, 1.5M-Baud Serial Consoles, and Power-Pull Survival on a $35 Single Board Computer*). 

The article walks through the visceral reality of hardware bring-up: why consumer SBCs are not plug-and-play cloud instances, how to wire serial logic analyzers, why passive aluminum cooling works when engineered properly, how Linux kernel dirty page writeback protects flash memory from wear exhaustion, and why the power-pull test is the ultimate litmus test for any physical home appliance.

## What confused me / Key Insights

The greatest realization from Week 01 is the fundamental difference between **cloud engineering** and **appliance engineering**:

In cloud software engineering (AWS, GCP), you treat infrastructure as an infinite, clean abstraction. Power is guaranteed by datacenter generators, storage is backed by redundant SAN arrays with infinite write endurance, and network ports are managed by cloud load balancers.

In appliance engineering, you have to embrace the physics of the machine:
- The flash memory will physically degrade if you log too aggressively to disk.
- The SoC will throttle and drop frames if you don't calculate heatsink surface area.
- The user will pull the power cord out of the wall without typing `sudo shutdown`.
- The ISP will place the home behind Carrier-Grade NAT.

Designing around these physical constraints from Day 01 is what turns a hobbyist Raspberry Pi toy into an indestructible personal cloud appliance.

## Tomorrow

Tomorrow we kick off **Week 02 — Networking, properly**. We will map our entire home network topology, serve our first HTTP endpoints, capture and inspect raw packet frames with `tcpdump`, and execute our deliberate network failure laboratory.
