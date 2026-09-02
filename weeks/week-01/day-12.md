# Day 12 — The Power-Pull and The 24-Hour Soak

**Week:** 01 · **Date:** 2026-09-02 · **Hours:** ~6.0

Today was the most nerve-wracking day of the hardware bring-up phase. In Part 6 of the master roadmap, under the heading *Pre-committed cuts*, there is a short, uncompromising sentence: **"Never cut: the enclosure, the two-account demo, the power-pull test, or the demo rehearsal."** 

Today, we executed the power-pull test.

## What I actually did

If you build a server for an enterprise datacenter, you assume uninterrupted power supplies (UPS), redundant power distribution units, and clean ACPI shutdown signals. But `sdrive` is designed to live on a bookshelf in a living room. In a home environment, an appliance *will* be unplugged by accident, a vacuum cleaner will trip a breaker, or the power grid will flicker during a thunderstorm.

If a personal photo appliance corrupts its ext4 journal, bricks its database, or leaves corrupted zero-byte files on disk after an ungraceful power cut, it is fundamentally defective.

### 1. The Test Harness (`power-pull-test.sh`)
I wrote an automated stress test script (`scripts/power-pull-test.sh`) designed to simulate heavy, continuous disk I/O. The script generates sequential 1MB binary blocks filled with pseudorandom data, calculates their SHA-256 checksums, writes the hash to an append-only manifest file, and executes a hardware `sync -d` to force the kernel page cache to physically flush the blocks to the microSD flash NAND.

I launched the write loop over SSH:
```bash
./scripts/power-pull-test.sh write
```

I watched the counter tick up rapidly on my terminal: Block #100... Block #200... Block #300...

### 2. Yanking the Cord
At block **#342**—right in the middle of active, heavy random I/O write operations—I reached behind the board and physically yanked the USB Type-C power cable straight out of the Radxa ROCK 3C.

The LEDs died instantly. The SSH terminal froze. The room went silent.

There is always a split second of dread when you intentionally cut power to a bare embedded Linux board. You wonder if the flash controller just scrambled a critical superblock or if the partition table became unreadable garbage.

### 3. The Recovery Capture (UART2)
I waited ten seconds, plugged the USB-C power supply back into the board, and monitored the serial console in `picocom` at 1,500,000 baud.

The boot sequence was clean and decisive:
- **0.2s:** Rockchip DDR training passed (`1056MHz pass!`).
- **1.1s:** U-Boot SPL loaded the Linux 6.6 kernel and device tree into RAM.
- **1.4s:** The ext4 filesystem driver mounted the root partition in read-only mode and immediately detected the dirty shutdown state:
  ```text
  [ 1.448912] EXT4-fs (mmcblk0p1): INFO: recovery required on readonly filesystem
  [ 1.450124] EXT4-fs (mmcblk0p1): write access will be enabled during recovery
  [ 1.451890] EXT4-fs (mmcblk0p1): recovery complete
  [ 1.452410] EXT4-fs (mmcblk0p1): mounted filesystem 5a7c3b2e-... r/w with ordered data mode.
  ```
- **7.1s:** Systemd reached `Multi-User System`, started OpenSSH, launched `sdrive-health-watchdog`, and initialized the Tailscale WireGuard interface.

The ext4 journal replayed all uncommitted metadata in less than **3 milliseconds**.

### 4. Mathematical Verification (`--verify`)
The moment the board came back online, I SSH'd in and executed the verification suite:

```bash
sdrive-admin@sdrive-node1:~$ ./scripts/power-pull-test.sh --verify
```

The script iterated through all 341 recorded blocks in the manifest, re-reading every single megabyte from flash and computing fresh SHA-256 hashes against the pre-crash manifest records.

**The result was flawless:**
- Total blocks recorded in manifest: **341 (341 MB)**.
- Verified intact blocks: **341 / 341 (100.0% match)**.
- Corrupted blocks detected: **0**.
- Corrupted inodes / filesystem errors: **0**.

### 5. The 24-Hour Soak Test Audit
I wrapped up the day by reviewing the continuous 24-hour telemetry captured by `sdrive-health-watchdog.service`.

Across a full 24-hour continuous burn-in:
- **System Uptime:** 24h 00m with zero kernel panics or OOM events.
- **Memory Footprint:** Completely flat line at **182 MB RAM** utilization (leaving 3.8GB of RAM available for page cache).
- **Thermal Range:** SoC temperature fluctuated between **35.8°C** and **37.1°C** at idle, never exceeding 42°C during background tasks.
- **Network Link:** Zero dropped packets across Ethernet and 100% WireGuard tunnel uptime over Tailscale.

I committed the full test report to `benchmarks/week-01-power-pull-resilience.md`.

## What confused me

The primary area of research today was diving into ext4 journaling modes. 

Linux ext4 supports three distinct journaling modes: `data=journal` (logs all data and metadata, highest write amplification), `data=ordered` (logs only metadata, but guarantees data blocks are written before metadata commits), and `data=writeback` (logs metadata without ordering constraints, fastest but risks stale data in files on crash).

Armbian defaults to **`data=ordered`**. Today's test proved why `data=ordered` is the engineered sweet spot for an embedded appliance: by enforcing that data blocks are flushed before metadata transactions commit to the journal, it guarantees that any file recorded in the directory tree is mathematically valid and never contains zeroed garbage after an ungraceful reboot, all while avoiding the 2x write amplification penalty of `data=journal`.

## Tomorrow

Tomorrow is Day 13 (Week 01 Day 06 / Retro Day): **The Week 01 Retrospective and Second Long-Form Technical Article**. We will complete `weeks/week-01/retro.md`, write our essay on embedded Linux bring-up, serial debugging, and flash resilience, and prepare for Week 02: **Networking, properly**.
