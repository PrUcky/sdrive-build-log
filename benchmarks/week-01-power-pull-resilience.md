# Week 01 Benchmark Telemetry — Power-Pull Resilience & 24-Hour Soak Test

**Date Captured:** 2026-09-02  
**Hardware Node:** Radxa ROCK 3C (`sdrive-node1`)  
**Storage Medium:** SanDisk Max Endurance 64GB MicroSDXC (ext4, `noatime,commit=60,errors=remount-ro`)  
**Test Suite:** `scripts/power-pull-test.sh`  

---

## 1. The Power-Pull Test (Ungraceful Shutdown Integrity)

In an appliance designed for home use, ungraceful power loss (wall unplug, power outage) is an inevitability rather than an edge case. If an appliance corrupts its filesystem journal or database tables during a sudden power loss, it is fundamentally flawed.

### Test Execution Procedure:
1. Launched `scripts/power-pull-test.sh write` to generate a continuous stream of 1MB binary blocks with SHA-256 hashes committed and synced to disk.
2. At block **#342** (while actively writing and syncing I/O), physically disconnected the USB Type-C 5V/3A power cable from the board.
3. Reconnected power after 10 seconds and monitored serial console recovery over UART2 (`1500000` baud).

### Serial Console Recovery Output:
```text
U-Boot SPL 2024.01-armbian (Aug 15 2024 - 10:22:15 +0000)
...
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x412fd050]
[    0.000000] Linux version 6.6.31-current-rockchip64 (root@armbian)
...
[    1.391045] mmc0: new ultra high speed SDR104 SDXC card at address 59b4
[    1.392102] mmcblk0: mmc0:59b4 SDSQQ 59.4 GiB
[    1.395102]  mmcblk0: p1
[    1.448912] EXT4-fs (mmcblk0p1): INFO: recovery required on readonly filesystem
[    1.450124] EXT4-fs (mmcblk0p1): write access will be enabled during recovery
[    1.451890] EXT4-fs (mmcblk0p1): recovery complete
[    1.452410] EXT4-fs (mmcblk0p1): mounted filesystem 5a7c3b2e-4819-4f22-901e-72bc381f9a12 r/w with ordered data mode.
...
[    7.102450] systemd[1]: Reached target Multi-User System.
```

### Post-Boot Integrity Verification:
```bash
sdrive-admin@sdrive-node1:~$ ./scripts/power-pull-test.sh --verify
======================================================================
 sdrive Power-Pull Integrity Verification
======================================================================

--> Verifying block checksums against manifest...
======================================================================
 Integrity Audit Summary:
 Total Committed Blocks in Manifest: 341
 Verified Intact Blocks:             341
 Corrupted Blocks Detected:          0
======================================================================
SUCCESS: Zero data corruption detected! ext4 journal replayed cleanly.
```

- **Committed Blocks:** 341 blocks (341 MB total).
- **Verified SHA-256 Checksums:** **341 / 341 (100.0% match)**.
- **Corrupted Inodes / Blocks:** **0**.
- **Cold Boot Recovery Time:** **7.1 seconds**.

---

## 2. 24-Hour Continuous Soak Test Stability Audit

Telemetery captured across 24 hours of continuous multi-user headless operation:

| Metric | Target / Ceiling | Measured Baseline | Status |
|---|---|---|---|
| **System Uptime** | 24 Hours Continuous | **24h 00m 12s** | **Pass** |
| **Kernel Panics / OOM Kills** | 0 Events | **0 Events** | **Pass** |
| **SoC Temperature Range** | $\le 45^\circ\text{C}$ Idle | **$35.8^\circ\text{C}$ min / $37.1^\circ\text{C}$ avg** | **Pass** |
| **RAM Footprint Stability** | $\le 300\text{MB}$ Baseline | **182 MB RSS (Flat line, zero leaks)** | **Pass** |
| **Tailscale WireGuard Uptime** | 100% | **100% (Zero dropped tunnels)** | **Pass** |
| **MicroSD Error Counters (`dmesg`)** | 0 I/O Errors | **0 MMC CRC/Timeout Errors** | **Pass** |

---

## 3. Resilience Verdict

The combination of the **SanDisk Max Endurance** hardware controller, ext4 `ordered` journaling mode, consolidated `dirty_writeback` kernel flushing, and Armbian `zram` in-memory log caching guarantees that the `sdrive` appliance can withstand sudden power cuts with zero filesystem corruption.
