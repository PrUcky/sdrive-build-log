# Day 10 — The Stress Test and The Line Rate

**Week:** 01 · **Date:** 2026-08-31 · **Hours:** ~6.5

With remote SSH access hardened and our health watchdog active, today was dedicated to pushing the physical board to its absolute limits. Before we start stacking container runtimes, PostgreSQL databases, and S3 daemons on top of this machine in Weeks 02 and 03, I needed to establish the ground-truth baseline for two critical physical boundaries: **thermal dissipation under sustained 100% CPU load**, and **raw network throughput over Gigabit Ethernet**.

## What I actually did

I structured today’s engineering session around three benchmarking suites: synthetic CPU stress testing, network throughput saturation, and automated node provisioning.

### 1. The 15-Minute Thermal Torture Test
Yesterday, our watchdog showed the Rockchip RK3566 idling at a comfortable 36.4°C while downclocked to 408MHz. But an idle baseline tells you nothing about what happens when multiple phones dump hundreds of photos and the server has to handle concurrent I/O.

To test the thermal limits, I connected my inline USB-C power meter to the power rail and initiated a 15-minute synthetic stress run using `stress-ng` across all four Cortex-A55 cores:

```bash
stress-ng --cpu 4 --cpu-method matrixprod --metrics-brief --timeout 15m
```

I monitored the temperature progression every 60 seconds by watching our `sdrive-health-watchdog` logs. 

The results exceeded my most optimistic expectations. As all four cores immediately ramped to their maximum clock of 1.8GHz, power draw jumped from 1.95W at idle to 4.35W under full load. The temperature climbed steadily through the first five minutes—hitting 44.1°C at minute 1, 48.6°C at minute 3, and 51.2°C at minute 5. By minute 10, the thermal curve began to flatten, and at minute 15, the SoC reached steady-state thermal equilibrium at **54.2°C** ($\Delta T = +17.8^\circ\text{C}$).

Rockchip’s thermal throttling threshold is hardcoded into the kernel device tree at **85°C**. Reaching thermal equilibrium at 54.2°C means our humble 20x20mm passive aluminum heatsink maintains over **30°C of thermal headroom** under continuous maximum CPU saturation without requiring a noisy cooling fan. That is a massive validation of the low-power RK3566 design choice we made in ADR 0002.

### 2. Saturating Gigabit Ethernet (`iperf3`)
Next, I wanted to verify that the board's Realtek RTL8211F Gigabit Ethernet transceiver and the Linux kernel's `rk_gmac-dwmac` network driver could actually saturate a 1Gbps home network link without dropping packets or bottlenecking on interrupts.

I ran `iperf3 -s` on the ROCK 3C (`192.168.1.150`) and initiated a 10-stream, 30-second TCP benchmark from my workstation over a Cat6 patch cable:

```bash
iperf3 -c 192.168.1.150 -P 10 -t 30
```

The transfer results were virtually textbook:
- **TCP Line Rate:** **941 Mbps** sustained across the 30-second window.
- **TCP Retransmissions:** Exactly **0 retransmits**, proving zero packet loss across the switch and Ethernet PHY.
- **UDP Jitter Test:** Saturated **956 Mbps** with an average jitter of just **0.021 ms**.

During the 941 Mbps network transfer, total board power consumption rose slightly to 3.47W while SoC temperature stayed at 42.1°C. The Ethernet controller and kernel TCP stack handle line-rate ingestion with effortless stability.

### 3. Flash Storage I/O Baseline (`fio`)
Before wrapping up the benchmarks, I ran a direct I/O storage profile against our SanDisk Max Endurance 64GB microSD card using `fio`. 

Sequential writes clocked in at **42.8 MB/s**, sequential reads reached **88.4 MB/s**, and random 4K mixed read/write tests yielded **2,410 read IOPS** and **804 write IOPS** with an average latency of 3.2ms. For the prototype phase, 43 MB/s of sequential write speed is more than quadruple the bandwidth needed to absorb typical 100Mbps camera backup streams.

I compiled all telemetry data, power figures, and test logs into a permanent reference document at `benchmarks/week-01-thermal-network-baseline.md`.

### 4. Codifying the System: `bootstrap-node.sh` & Flash Protection
To ensure that all these system configurations are reproducible on any future spare board, I wrote an idempotent provisioning script: `scripts/bootstrap-node.sh`.

The script handles complete OS hardening in a single command:
- Installs necessary diagnostics (`fio`, `iperf3`, `htop`, `ufw`, `jq`).
- Applies Linux kernel `sysctl` network buffer tuning (`net.core.rmem_max=16MB`, `net.core.wmem_max=16MB`, `vm.swappiness=10`) to optimize socket queues and prevent unnecessary flash swap writes.
- Deploys `config/systemd/journald.conf.d/01-sdrive-caps.conf`, which places a strict **100MB hard ceiling** on `systemd-journald` disk usage to protect the microSD card from log bloat.
- Configures the `ufw` firewall to enforce a default-deny inbound policy while explicitly allowlisting SSH (port 22) and the `tailscale0` overlay interface.

## What confused me

During the initial `iperf3` run with a single TCP stream (`-P 1`), throughput stalled around 720 Mbps rather than hitting the 940 Mbps line rate. 

I initially suspected Ethernet interrupt moderation on the ARM core. However, after inspecting the Linux network sysctl defaults, I found that the default TCP receive window buffer (`net.ipv4.tcp_rmem` default of 128KB) was too conservative to allow the TCP congestion window to scale rapidly on Linux 6.6. Once I bumped `net.core.rmem_max` and `net.core.wmem_max` to 16MB in our `sysctl.d` configuration, single-stream throughput immediately snapped to 938 Mbps and multi-stream hit 941 Mbps.

The second minor headache was testing UFW firewall rules. When I enabled UFW, it initially blocked incoming broadcast DHCP renewal packets on `eth0`. I resolved this by ensuring UFW's default `before.rules` preserved standard DHCP client packet traversal.

## Tomorrow

Tomorrow is Day 11: **The Mesh Overlay & WireGuard Transport**. We will install and authenticate the Tailscale daemon on the board, configure MagicDNS hostnames (`sdrive-node1.ts.net`), verify direct peer-to-peer WireGuard connections over 5G cellular, and capture our first encrypted mesh throughput numbers.
