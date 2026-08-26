# Benchmarking Methodology & Telemetry Plan

To ensure the `sdrive` appliance meets its production durability, thermal stability, and ingestion latency targets across the 12-week roadmap, all performance metrics will be captured using standardized, reproducible test suites.

---

## 1. Power Consumption Benchmarks

### Measurement Apparatus:
- Inline USB Type-C Power Meter (measuring voltage, current, watts, and total mWh accumulated).
- Input Supply: Fixed 5.1V / 3.0A regulated DC rail.

### Test Cases:
1. **Cold Boot Transient Peak:** Peak wattage observed during U-Boot and Linux kernel device tree initialization (first 10 seconds).
2. **Steady-State Headless Idle:** Wattage measured after 30 minutes of multi-user systemd uptime with Ethernet link established and no active clients.
3. **Sustained Ingestion Load:** Wattage measured during continuous 50GB encrypted photo ingestion (concurrent 100Mbps upload stream to Garage S3 over Tailscale).
4. **Synthetic Max Load:** All 4 Cortex-A55 cores loaded via `stress-ng --cpu 4 --cpu-method matrixprod` for 15 minutes.

---

## 2. Thermal Stability & Throttling Limits

### Measurement Points:
- SoC Thermal Zone 0 (`/sys/class/thermal/thermal_zone0/temp`).
- Ambient Room Temperature: Normalized to $24^\circ\text{C} \pm 1^\circ\text{C}$.

### Success Criteria:
- **Idle Temp (Passive Heatsink):** $\le 42^\circ\text{C}$.
- **Sustained Upload Temp:** $\le 58^\circ\text{C}$.
- **Max Stress Temp (100% CPU):** $\le 72^\circ\text{C}$ (below the RK3566 thermal throttling knee point of $85^\circ\text{C}$).

---

## 3. Storage I/O Profiling (`fio`)

### Target Drives:
- Prototype Boot: SanDisk Max Endurance 64GB MicroSD (SD 3.0 UHS-I).
- Production Storage: WD Blue SN580 500GB NVMe SSD (PCIe 2.1 x1 mode).

### Standard Test Suites:
```bash
# 1. Sequential Write Throughput (Large Blobs / Videos)
fio --name=seq_write --ioengine=libaio --rw=write --bs=1M --size=2G \
    --numjobs=1 --direct=1 --group_reporting --filename=/var/lib/garage/data/fio_test

# 2. Sequential Read Throughput (Media Playback)
fio --name=seq_read --ioengine=libaio --rw=read --bs=1M --size=2G \
    --numjobs=1 --direct=1 --group_reporting --filename=/var/lib/garage/data/fio_test

# 3. Random 4K Mixed Read/Write (PostgreSQL Database Workload)
fio --name=rand_4k --ioengine=libaio --rw=randrw --rwmixread=75 --bs=4k \
    --size=1G --numjobs=4 --direct=1 --group_reporting --filename=/var/lib/postgresql/fio_test
```

---

## 4. Network Throughput & Jitter (`iperf3`)

### Test Scenarios:
1. **Bare LAN Gigabit Baseline:** Direct TCP/UDP stream from laptop to ROCK 3C over Cat6 Ethernet switch. Target: $\ge 940\text{ Mbps}$.
2. **Tailscale WireGuard Mesh Throughput:** P2P encrypted stream over local Wi-Fi. Target: $\ge 450\text{ Mbps}$ (measuring RK3566 ChaCha20/Poly1305 software encryption throughput).
3. **Remote 5G Ingestion Stream:** Real-world cellular throughput over Tailscale DERP/STUN hole-punching.
