# Embedded Storage Architecture & Flash Durability Strategy

This document outlines the multi-tiered storage architecture, flash endurance protections, and filesystem parameters engineered for the `sdrive` appliance.

---

## 1. Physical Storage Hierarchy

```
+-----------------------------------------------------------------------------+
| TIER 0: Volatile Fast RAM Cache (LPDDR4 - 4GB Pool)                         |
| - Linux Page Cache (Buffers active inodes, directory entries, S3 chunks)    |
| - In-Memory ZRAM Overlay: Compressed `/var/log` (zram1) + Swap (zram0)      |
+-----------------------------------------------------------------------------+
                                     |
                       [ Periodic Sync / Writeback ]
                                     |
+-----------------------------------------------------------------------------+
| TIER 1: Operating System & Metadata Storage (v1: MicroSD / v2: eMMC 5.1)    |
| - Root Filesystem (`/`): Linux kernel, systemd units, configuration files   |
| - Database Storage (`/var/lib/postgresql`): Relational metadata tables       |
| - Garage Metadata (`/var/lib/garage/meta`): High-speed LMDB object index    |
+-----------------------------------------------------------------------------+
                                     |
                       [ Dedicated Direct Storage Bus ]
                                     |
+-----------------------------------------------------------------------------+
| TIER 2: High-Volume Ciphertext Blob Storage (v2: NVMe M.2 2280 SSD)         |
| - Garage Data Pool (`/var/lib/garage/data`): Raw encrypted photo/video blobs |
| - PCIe 2.1 x1 Interface (~500 MB/s bandwidth)                                |
+-----------------------------------------------------------------------------+
```

---

## 2. Flash Durability & Write Amplification Mitigation

Consumer flash storage (especially microSD cards) is highly susceptible to **Write Amplification Factor (WAF)**. When an operating system executes thousands of continuous small (512-byte to 4KB) writes (such as daemon access logs and database WAL flushes), the flash controller is forced to repeatedly erase and rewrite entire 2MB to 4MB flash blocks, rapidly burning through the physical Program/Erase (P/E) cycles of the NAND cells.

### sdrive Flash Protection Mechanisms:

1. **In-Memory Logging via Armbian `zram` Overlay:**
   - `/var/log` is mounted on an in-memory compressed block device (`/dev/zram1`).
   - Log writes are absorbed entirely in RAM.
   - The `armbian-ramlog` daemon flushes log snapshots to disk only once per hour and upon clean system shutdown.

2. **Systemd Journal Hard Quotas (`01-sdrive-caps.conf`):**
   - Hard cap of **100MB** placed on persistent systemd journal storage.
   - Prevents misbehaving or noisy third-party services from exhausting disk space.

3. **Consolidated Kernel Dirty Page Writeback:**
   - Configured `vm.dirty_background_ratio = 5` and `vm.dirty_writeback_centisecs = 1500` in `/etc/sysctl.d/99-sdrive-zram-storage.conf`.
   - Small writes are coalesced in the Linux page cache for up to 15 seconds before being committed as contiguous sequential block writes to flash.

4. **Periodic TRIM Discard (`fstrim.timer`):**
   - Enabled weekly `fstrim` jobs across all mounted ext4 partitions.
   - Informs the flash controller’s Wear Leveling algorithms which blocks are free, maintaining write performance and extending lifespan.

---

## 3. Filesystem Mount Configuration (`/etc/fstab`)

All persistent partitions are mounted by explicit **UUID** to prevent boot failures if block device assignment order (`/dev/mmcblk0` vs `/dev/sda` vs `/dev/nvme0n1`) changes across kernel revisions.

```text
# /etc/fstab baseline for sdrive appliance
UUID=5a7c3b2e-4819-4f22-901e-72bc381f9a12  /      ext4  defaults,noatime,commit=60,errors=remount-ro  0  1
UUID=a83b9c1d-1234-4567-89ab-cdef01234567  /data  ext4  defaults,noatime,commit=60,nofail             0  2
```

### Mount Option Rationale:
- **`noatime`**: Disables updating the access timestamp inode attribute every time a file or photo is read. Completely eliminates write operations during read-only album browsing.
- **`commit=60`**: Instructs the ext4 journaling thread to commit data and metadata to disk every 60 seconds (instead of the default 5 seconds), consolidating random write batches.
- **`errors=remount-ro`**: Automatically remounts the root filesystem as read-only if hardware I/O corruption is detected, preventing cascade data corruption.
