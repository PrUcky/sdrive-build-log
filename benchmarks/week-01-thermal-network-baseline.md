# Week 01 Benchmark Telemetry — Thermal, Power & Network Baseline

**Date Captured:** 2026-08-31  
**Hardware Node:** Radxa ROCK 3C (Rockchip RK3566, 4GB LPDDR4)  
**OS:** Armbian 24.5.1 Bookworm (Linux 6.6.31-current-rockchip64)  
**Ambient Room Temperature:** $24.2^\circ\text{C} \pm 0.5^\circ\text{C}$  
**Cooling:** Anodized Aluminum Passive Heatsink (20x20x10mm) with 3M 8810 adhesive.

---

## 1. Power Consumption Baseline (Inline USB-C Meter)

Power measurements captured using an inline USB-C power meter on the 5.1V regulated DC supply rail.

| Operating State | Measured Voltage (V) | Current Draw (mA) | Power Draw (Watts) | Thermal Status | Notes |
|---|---|---|---|---|---|
| **Cold Boot Peak** | 5.08 V | 1,420 mA | **7.21 W** | $31.0^\circ\text{C}$ | U-Boot SPL + Kernel decompression (transient 2.5s spike). |
| **Steady-State Headless Idle** | 5.12 V | 380 mA | **1.95 W** | $36.4^\circ\text{C}$ | SSH daemon + health watchdog active; CPU downclocked to 408MHz. |
| **Gigabit Network Ingestion (`iperf3`)** | 5.10 V | 680 mA | **3.47 W** | $42.1^\circ\text{C}$ | Saturated 941 Mbps TCP stream over Realtek RTL8211F PHY. |
| **Sustained 100% CPU Stress (`stress-ng`)** | 5.06 V | 860 mA | **4.35 W** | $54.2^\circ\text{C}$ | All 4 Cortex-A55 cores pinned at 1.8GHz for 15 minutes. |

---

## 2. Thermal Dissipation & Stress Test (`stress-ng`)

Test command executed over SSH:
```bash
stress-ng --cpu 4 --cpu-method matrixprod --metrics-brief --timeout 15m
```

### Thermal Progression Log (Every 60 Seconds):

| Elapsed Time | CPU Clock (MHz) | CPU Utilization | SoC Temperature | Temperature Rise ($\Delta T$) | Throttling Status |
|---|---|---|---|---|---|
| **0 min (Idle)** | 408 MHz | 0.8% | $36.4^\circ\text{C}$ | $+0.0^\circ\text{C}$ | Normal (No Throttling) |
| **1 min** | 1800 MHz | 100.0% | $44.1^\circ\text{C}$ | $+7.7^\circ\text{C}$ | Normal |
| **3 min** | 1800 MHz | 100.0% | $48.6^\circ\text{C}$ | $+12.2^\circ\text{C}$ | Normal |
| **5 min** | 1800 MHz | 100.0% | $51.2^\circ\text{C}$ | $+14.8^\circ\text{C}$ | Normal |
| **8 min** | 1800 MHz | 100.0% | $53.0^\circ\text{C}$ | $+16.6^\circ\text{C}$ | Normal |
| **10 min** | 1800 MHz | 100.0% | $53.8^\circ\text{C}$ | $+17.4^\circ\text{C}$ | Normal |
| **15 min (Equilibrium)** | 1800 MHz | 100.0% | **$54.2^\circ\text{C}$** | $+17.8^\circ\text{C}$ | **Pass (30.8°C below 85°C trip point)** |
| **+3 min (Cooldown)** | 408 MHz | 1.1% | $39.5^\circ\text{C}$ | $+3.1^\circ\text{C}$ | Normal |

**Conclusion:** The passive aluminum heatsink completely dissipates the RK3566's 4.35W maximum thermal output. At thermal equilibrium ($54.2^\circ\text{C}$), the SoC maintains over **30°C of thermal headroom** below Rockchip’s $85^\circ\text{C}$ thermal throttling threshold.

---

## 3. Gigabit Ethernet Throughput Profiling (`iperf3`)

- **Server Node:** Radxa ROCK 3C (`192.168.1.150`, GbE RTL8211F PHY).
- **Client Node:** Workstation (`192.168.1.100`, Intel I225-V 2.5GbE).
- **Link Topology:** Direct Cat6 patch cables into a Netgear Gigabit unmanaged switch (MTU 1500).

### TCP Stream Test (10 Streams, 30s Duration):
```text
[ ID] Interval           Transfer     Bitrate         Retr
[SUM]   0.00-30.00  sec  3.29 GBytes   941 Mbits/sec    0             sender
[SUM]   0.00-30.00  sec  3.28 GBytes   940 Mbits/sec                  receiver
```
- **TCP Throughput:** **941 Mbps** (94.1% of theoretical Gigabit line rate).
- **TCP Retransmissions:** **0 packets** (Zero packet drops on the PHY layer).

### UDP Throughput & Jitter Test (Bandwidth target: 1000M, 30s Duration):
```text
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total Datagrams
[  5]   0.00-30.00  sec  3.34 GBytes   956 Mbits/sec  0.021 ms  12/244512 (0.0049%)
```
- **UDP Throughput:** **956 Mbps**.
- **Jitter:** **0.021 ms**.

---

## 4. MicroSD Storage I/O Profiling (`fio`)

Target drive: **SanDisk Max Endurance 64GB MicroSDXC** (UHS-I SDR104 mode).

```bash
# Sequential Write (2GB direct I/O, bs=1M)
Throughput: 42.8 MB/s | IOPS: 42

# Sequential Read (2GB direct I/O, bs=1M)
Throughput: 88.4 MB/s | IOPS: 88

# Random 4K Mixed 75/25 (1GB direct I/O, 4 jobs)
Read IOPS: 2,410 IOPS (9.64 MB/s) | Write IOPS: 804 IOPS (3.21 MB/s)
Average Latency: 3.2 ms
```

**Assessment:** The SanDisk Max Endurance card easily sustains ~43 MB/s sequential writes. For the prototype phase, this is more than sufficient to absorb multiple concurrent 100Mbps upload streams without blocking the storage queue.
