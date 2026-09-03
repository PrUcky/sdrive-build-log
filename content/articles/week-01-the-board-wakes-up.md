# The Board Wakes Up: Bring-up, 1.5M-Baud Serial Consoles, and Power-Pull Survival on a $35 Single Board Computer

*By Pratyush Chaudhary · September 3, 2026 · 14 min read*

```
                     +----------------------------------+
                     |        Radxa ROCK 3C Node        |
                     |  Rockchip RK3566 (Quad A55)      |
                     |  4GB LPDDR4 | 1.95W Idle Draw    |
                     +-----------------+----------------+
                                       |
                     [ UART2 Serial @ 1.5M Baud ]
                                       |
    +----------------------------------v----------------------------------+
    | U-Boot SPL -> Linux 6.6 LTS -> ext4 (ordered) -> Tailscale Mesh     |
    +---------------------------------------------------------------------+
```

---

## 1. The Shock of the Physical World

Modern software engineering is built on comfortable lies. 

When you spin up an EC2 instance or deploy a Docker container to a Kubernetes cluster, the cloud provider shields you from physical reality. The power supply never sags. The storage controller never wears out from excessive logging. The network packets arrive at a clean virtual interface without electrical noise or Carrier-Grade NAT collisions. If a virtual machine crashes, hypervisors resurrect it on another node in milliseconds.

When you decide to build a self-hosted, zero-knowledge personal cloud appliance on physical hardware that will live on a bookshelf in someone's home, those comfortable abstractions vanish.

You are suddenly forced to confront the physics of computation:
- Will this \$35 board overheat and throttle when a mobile phone dumps 500 photos over Wi-Fi?
- Will the operating system eat through the Program/Erase (P/E) cycles of the flash storage in four months of database logging?
- What happens when someone trips over the power cord and yanks the 5V DC plug out of the wall while the database is committing a transaction?

This week, we took `sdrive` from an abstract architectural blueprint of cryptography and storage engines into a living, physical machine: the **Radxa ROCK 3C**. This is the engineering chronicle of our hardware bring-up, our battle with 1.5-megabaud serial interfaces, and the moment we intentionally yanked the power cord to see if our filesystem would survive.

---

## 2. The Silicon Foundation: Rockchip RK3566 & Passive Cooling

In [Architectural Decision Record 0002](../../docs/adr/0002-hardware-platform-radxa-rock-3c.md), we selected the **Radxa ROCK 3C** over the Raspberry Pi 4. The reasoning came down to three hardware attributes:

1. **Rockchip RK3566 SoC:** A monolithic 22nm quad-core ARM Cortex-A55 processor clocked up to 1.8GHz. Unlike high-power big.LITTLE architectures that generate 10–15 Watts of heat, the RK3566 draws less than **2.0 Watts at idle** and caps out at **4.35 Watts under full CPU saturation**.
2. **Dedicated Storage Interfaces:** A native eMMC 5.1 connector on the board top, and an M.2 PCIe 2.1 x1 slot underneath the PCB capable of driving NVMe solid-state drives without sharing USB 3.0 bus bandwidth.
3. **Onboard Gigabit Ethernet PHY:** A Realtek RTL8211F transceiver wired directly to the SoC's internal GMAC interface.

```
+-------------------------------------------------------------+
|               Radxa ROCK 3C Physical Layout                 |
|                                                             |
|  [USB-C Power 5V/3A]   [Realtek RTL8211F GbE]   [USB 3.0]   |
|         │                        │                  │       |
|  +──────┴────────────────────────┴──────────────────┴────+  |
|  |  [Rockchip RK3566 SoC] + [20x20x10mm Aluminum Heatsink]|  |
|  |  4x ARM Cortex-A55 @ 1.8GHz                           |  |
|  +───────────────────────────────────────────────────────+  |
|         │                                                   |
|  [40-Pin GPIO (UART2)]                 [SanDisk MicroSD]    |
+-------------------------------------------------------------+
```

### The Thermal Equation: Why Fans Are an Anti-Pattern
A home appliance cannot have a fan. Small 30mm cooling fans found in single-board computer kits are noisy, high-pitched, gather dust, and invariably suffer bearing failures within 18 months.

Our design constraint was strict: **100% passive aluminum dissipation**.

Before applying power to the board for the first time, we mounted a custom $20 \times 20 \times 10\text{ mm}$ black anodized aluminum heatsink directly onto the RK3566 silicon package using 3M 8810 thermally conductive adhesive tape ($0.60\text{ W/m}\cdot\text{K}$).

To verify whether passive cooling was sufficient, we initiated a 15-minute synthetic stress run using `stress-ng` with all four Cortex-A55 cores executing matrix multiplication at 1.8GHz:

```bash
stress-ng --cpu 4 --cpu-method matrixprod --metrics-brief --timeout 15m
```

```
SoC Temperature vs. Time (15-Minute Full Load @ 1.8GHz)
60°C |
55°C |                                   *---*---*---* (54.2°C Equilibrium)
50°C |                       *---*---*---*
45°C |           *---*---*---*
40°C |   *---*---*
35°C |---* (36.4°C Idle)
     +--------------------------------------------------------
       0m  1m  2m  3m  4m  5m  6m  7m  8m  10m 12m 15m
```

At minute 15, the temperature leveled off at **$54.2^\circ\text{C}$** ($\Delta T = +17.8^\circ\text{C}$ above room ambient). The Rockchip kernel thermal throttle point is hardcoded at **$85.0^\circ\text{C}$**. The passive aluminum heatsink gives us **over 30°C of thermal headroom** under continuous 100% CPU load without emitting a decibel of noise.

---

## 3. The 1,500,000 Baud Serial Surprise

The first golden rule of embedded systems engineering is simple: **Connect the hardware serial console before you ever touch the network.**

If a headless board fails to boot because of a corrupted device tree, bad memory timings, or a missing root filesystem UUID, the network stack will never initialize. An SSH connection will simply time out. Without a serial console, you are flying blind in total darkness.

The ROCK 3C exposes **UART2** on its 40-pin GPIO header:
- **Pin 6:** Ground (GND)
- **Pin 8:** UART2_TX (Transmit $\rightarrow$ CP2102 RXD)
- **Pin 10:** UART2_RX (Receive $\leftarrow$ CP2102 TXD)

```
[ Radxa ROCK 3C 40-Pin Header ]               [ Silicon Labs CP2102 ]
 Pin 6  (GND) ────────────────────────────────── GND
 Pin 8  (TXD) ────────────────────────────────── RXD
 Pin 10 (RXD) ────────────────────────────────── TXD
                                                  USB Type-A
                                                       │
                                              [ Dev Workstation ]
```

When we initially connected our serial terminal at the standard embedded rate of `115200` baud, the screen filled with unreadable garbage characters:

```text
\x00\xfa\x89\x12\xfe\xfe\x00\x1a\x88\x99...
```

This is a classic trap on Rockchip silicon. While the Raspberry Pi and Allwinner chips default to 115,200 baud, **Rockchip RK3566 boot ROM and U-Boot SPL run at 1,500,000 baud (1.5 Mbps)**.

Once we configured `picocom` to match:
```bash
picocom -b 1500000 /dev/ttyUSB0
```

The boot stream snapped into crystal-clear text:

```text
U-Boot SPL 2024.01-armbian (Aug 15 2024 - 10:22:15 +0000)
DDR4, 32bits, 2CS, X8_2PCS, total capacity=4096MB
channel[0] BW=32 Col=10 Bk=4 CS0 Row=16 CS1 Row=16 CS=2 Die BW=8 Size=4096MB
Change to: 1056MHz
...
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x412fd050]
[    0.000000] Linux version 6.6.31-current-rockchip64 (root@armbian)
[    1.391045] mmc0: new ultra high speed SDR104 SDXC card at address 59b4
[    1.451890] EXT4-fs (mmcblk0p1): recovery complete
[    1.452410] EXT4-fs (mmcblk0p1): mounted filesystem 5a7c3b2e-... with ordered data mode.
[    7.102450] systemd[1]: Reached target Multi-User System.
```

In 7.1 seconds, the board completed DDR training, decompressed the Linux 6.6 LTS kernel, mounted the root filesystem, and initialized systemd.

---

## 4. Flash Durability: Why SD Cards Die & How We Protect Them

The single most common hardware failure mode in hobbyist single-board computers is **microSD card corruption**.

Consumer flash storage is composed of NAND flash memory divided into erase blocks (typically 2MB to 4MB in size). When an operating system writes a tiny 512-byte log line to `/var/log/syslog`, the flash memory controller cannot rewrite just those 512 bytes. It must read the entire 2MB block into internal buffer RAM, erase the physical flash block, update the 512 bytes, and write all 2MB back to NAND.

This phenomenon is called **Write Amplification Factor (WAF)**. Under continuous logging, a service writing 10MB of actual log data per day can cause the controller to physically write **over 500MB** to the underlying NAND cells, burning through the card's limited Program/Erase cycles in a matter of months.

```
Write Amplification:
[ 512-byte log write ] ──> [ Flash Controller ] ──> [ 2MB-4MB NAND Block Erase & Rewrite! ]
```

### The sdrive Flash Protection Stack

To ensure that `sdrive` can run for years on flash storage without wearing out the medium, we implemented a four-tier flash durability architecture:

```
+-------------------------------------------------------------------------+
| Flash Durability Stack                                                  |
+-------------------------------------------------------------------------+
| 1. In-Memory Log Overlay : `/var/log` mounted on compressed RAM (zram1) |
| 2. Hard Quotas           : `systemd-journald` capped strictly at 100MB  |
| 3. Consolidated Flushing : `vm.dirty_background_ratio = 5` (15s delay)  |
| 4. Filesystem Flags      : `noatime,commit=60,errors=remount-ro`        |
+-------------------------------------------------------------------------+
```

1. **In-Memory Logging via Armbian `zram` Overlay:**
   `/var/log` is mounted on an in-memory compressed block device (`/dev/zram1`). Log entries generated by background daemons are written directly into RAM with `zstd` compression. The `armbian-ramlog` service flushes a consolidated log snapshot to flash only once per hour.
2. **Journald Hard Ceilings (`config/systemd/journald.conf.d/01-sdrive-caps.conf`):**
   ```ini
   [Journal]
   Storage=persistent
   SystemMaxUse=100M
   RuntimeMaxUse=50M
   RateLimitIntervalSec=30s
   RateLimitBurst=1000
   ```
3. **Delayed Kernel Dirty Page Flushing (`/etc/sysctl.d/99-sdrive-zram-storage.conf`):**
   By setting `vm.dirty_writeback_centisecs = 1500` (15 seconds) and `vm.vfs_cache_pressure = 50`, the Linux kernel coalesces random metadata updates in the page cache, writing them out in large, contiguous sequential bursts.
4. **Mount Options in `/etc/fstab`:**
   We mount the root ext4 partition with `noatime` (disabling inode access timestamp updates on file reads) and `commit=60` (extending filesystem journal commit intervals from 5s to 60s).

---

## 5. Squeezing the Pipe: Saturating Gigabit Ethernet

A photo storage appliance that transfers files at 10 MB/s over a local network is intolerable. When a user plugs the appliance into their home router via Cat6 Ethernet, the appliance must saturate the **1,000 Mbps (Gigabit) line rate**.

We ran `iperf3` between a desktop workstation and the ROCK 3C (`192.168.1.150`):

```bash
iperf3 -c 192.168.1.150 -P 10 -t 30
```

```
[ ID] Interval           Transfer     Bitrate         Retr
[SUM]   0.00-30.00  sec  3.29 GBytes   941 Mbits/sec    0             sender
[SUM]   0.00-30.00  sec  3.28 GBytes   940 Mbits/sec                  receiver
```

The transfer sustained **941 Mbps** (94.1% of theoretical wire speed, accounting for Ethernet and IP framing overhead) with **exactly 0 packet retransmissions**.

```
Throughput Benchmark Comparison:
Raw Gigabit Ethernet (TCP)   : [████████████████████████████████████████] 941 Mbps
Encrypted WireGuard Mesh (P2P): [████████████████████                      ] 462 Mbps
SanDisk Max Endurance Write  : [████████                                  ] 42.8 MB/s (342 Mbps)
```

### The Bandwidth-Delay Product (BDP) Tuning
During our first single-stream test, throughput stalled at 720 Mbps. The bottleneck was not CPU or hardware; it was default Linux socket buffer limits.

The Bandwidth-Delay Product ($\text{BDP} = \text{Bandwidth} \times \text{RTT}$) dictates how large TCP window buffers must be to keep a connection saturated without stalling for ACKs:

$$\text{BDP}_{\text{WAN}} = 100\text{ Mbps} \times 0.060\text{ s} = 750\text{ KB}$$

Default Linux 6.6 settings capped socket buffers at 128KB. By authoring `/etc/sysctl.d/99-sdrive-tuning.conf` with `net.core.rmem_max = 16777216` (16MB max buffer), TCP window scaling immediately unlocked full Gigabit line rate on the LAN and maximum throughput over cellular WAN.

---

## 6. The Invisible Mesh: Remote Access Without Port Forwarding

Self-hosting has historically failed for non-technical users because of one insurmountable barrier: **Carrier-Grade NAT (CGNAT)**.

Internet Service Providers no longer assign unique public IPv4 addresses to residential homes. Instead, hundreds of homes share a single public IP address. Opening a port in your home router's web interface is mathematically meaningless when your router sits behind an ISP-level NAT pool.

```
[ Mobile Phone (5G Cellular) ]
         │
         ├── 1. Discover Public UDP Endpoint (STUN) ──> [ Tailscale DERP Map ]
         │                                                      │
         └── 2. Direct P2P UDP Hole-Punch <─────────────────────┘
         │
[ WireGuard ChaCha20-Poly1305 Tunnel (MTU 1280) ]
         │
[ Radxa ROCK 3C (tailscale0: 100.64.0.10) ]
```

We solved this by deploying **Tailscale** on the appliance (`config/tailscale/tailscale-up.sh`). 

Using STUN (Session Traversal Utilities for NAT) and ICE hole-punching, Tailscale negotiates direct peer-to-peer UDP WireGuard connections between remote mobile devices and the home appliance.

### The Cellular Test
To test this, we disconnected our laptop from home Wi-Fi and tethered to a 5G cellular hotspot. 

We ran:
```bash
ssh sdrive-admin@sdrive-node1.ts.net
```

Within 28 milliseconds, the terminal dropped us into the shell. Zero router ports were opened. Zero dynamic DNS services were configured.

We benchmarked encrypted WireGuard throughput over the mesh (`iperf3 -c 100.64.0.10`):
- **Encrypted Throughput:** **462 Mbps** sustained.
- **Daemon Footprint:** **28.4 MB RAM** RSS.
- **Total CPU Load:** **20.7%** across the RK3566's four cores.

At 462 Mbps (57.7 MB/s), a 10MB raw camera photograph uploads across the encrypted mesh in **173 milliseconds**.

---

## 7. The Ultimate Litmus Test: Surviving the Power-Pull

In Part 6 of the master roadmap, there is an uncompromising rule: **"Never cut the power-pull test."**

In enterprise server software, ungraceful shutdowns are handled by battery backup units. In a home appliance, people trip over cables, turn off power strips, and experience local power cuts. If an appliance corrupts its filesystem when power drops, it is defective.

```
Power-Pull Execution Loop:
[ Loop: Write 1MB Random Data ] ──> [ SHA-256 Hash ] ──> [ Append Manifest ] ──> [ fsync to Flash ]
                                                                                         │
                                     [ *PHYSICAL POWER CORD PULLED AT BLOCK #342* ] <────┘
                                                                                         │
                               [ Reconnect Power -> U-Boot -> Linux ext4 Journal Replay ]
                                                                                         │
                                       [ Run `./scripts/power-pull-test.sh --verify` ]
                                       [ Result: 341 / 341 Blocks 100.0% SHA-256 Match ]
```

### The Test Execution
We wrote an automated test harness (`scripts/power-pull-test.sh`) that writes sequential 1MB pseudorandom binary blocks, computes their SHA-256 hashes, appends the hash to an on-disk manifest, and issues an explicit kernel `sync -d` to flush data and metadata to flash NAND.

At **Block #342**—in the middle of heavy, active, continuous random write I/O—we physically yanked the USB Type-C power cable out of the running board.

We plugged the power back in and watched the serial console:

```text
[    1.448912] EXT4-fs (mmcblk0p1): INFO: recovery required on readonly filesystem
[    1.450124] EXT4-fs (mmcblk0p1): write access will be enabled during recovery
[    1.451890] EXT4-fs (mmcblk0p1): recovery complete
[    1.452410] EXT4-fs (mmcblk0p1): mounted filesystem 5a7c3b2e-... with ordered data mode.
[    7.102450] systemd[1]: Reached target Multi-User System.
```

The ext4 journal replayed the uncommitted journal transaction in **under 3 milliseconds**.

We ran our verification audit:
```bash
./scripts/power-pull-test.sh --verify
```

```
======================================================================
 sdrive Power-Pull Integrity Verification
======================================================================
 Total Committed Blocks in Manifest: 341
 Verified Intact Blocks:             341
 Corrupted Blocks Detected:          0
======================================================================
SUCCESS: Zero data corruption detected! ext4 journal replayed cleanly.
```

All 341 committed blocks matched their SHA-256 checksums down to the last byte. Zero corrupted inodes. Zero truncated files. Zero filesystem errors.

---

## 8. Summary of Week 01 Metrics

| Metric | Target / Ceiling | Measured Performance | Status |
|---|---|---|---|
| **Hardware BOM Cost** | $< \$100.00$ | **\$68.40** (Board + Heatsink + Flash + Power + UART) | **PASS** |
| **Idle Board Power Draw** | $< 3.0\text{ W}$ | **1.95 W** (~$0.35 / month electricity) | **PASS** |
| **Peak Full Load Power Draw** | $< 10.0\text{ W}$ | **4.35 W** | **PASS** |
| **Peak SoC Temperature (100% Load)** | $< 70.0^\circ\text{C}$ | **54.2°C** ($>30^\circ\text{C}$ headroom below throttle) | **PASS** |
| **Raw Gigabit Line Rate (TCP)** | $> 900\text{ Mbps}$ | **941 Mbps** (0 packet retransmissions) | **PASS** |
| **WireGuard Mesh Throughput (TCP)** | $> 200\text{ Mbps}$ | **462 Mbps** (28MB RAM, 20.7% CPU load) | **PASS** |
| **Cold Boot Time to SSH Ready** | $< 15.0\text{ s}$ | **7.1 seconds** | **PASS** |
| **Power-Pull Data Integrity** | 100.0% Match | **100.0% Match** (0 corrupted blocks) | **PASS** |

---

## 9. What Comes Next: Week 02

With the physical hardware operational, thermally validated, network-accessible, and proven resilient to power loss, we leave the physical layer behind and move into **Week 02: Networking, properly**.

In Week 02, we will:
- Construct interactive network topology maps of our home subnet.
- Inspect raw Ethernet frames, ARP broadcasts, and TCP handshakes using `tcpdump`.
- Run our deliberate failure laboratory (`scripts/simulate-network-breakage.sh`) to diagnose port blocks, MTU fragmentation drops, and DNS blackholes using diagnostic tools instead of guesses.

The silicon is awake. The foundation is solid. Now we build the network.

---

*The full source code, scripts, configurations, and raw telemetry logs for Week 01 are open source and available at [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
