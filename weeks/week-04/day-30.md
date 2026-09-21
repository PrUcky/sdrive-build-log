# Day 30: The Blob Backup Pipeline and the Storage Architecture Bible

*September 21, 2026*

Sunday. Six hours. The metadata backup has been running automatically since yesterday — the first cron job fired at 3 AM and produced a clean 2.3 MB tar.gz of the PostgreSQL data, Garage SQLite index, and Museum state. But the metadata backup deliberately ignores the biggest component of the system: the actual encrypted photos. Those live in Garage's data volume and can grow to hundreds of gigabytes. Today I built the blob-level backup pipeline and wrote the authoritative storage architecture document.

## Why rsync and Not tar

The metadata backup uses `tar.gz` because the metadata is small (2–5 MB), changes slowly, and benefits from being a single atomic file that can be moved, emailed, or stored on a thumb drive. But `tar.gz` doesn't work for the blob tier.

Consider a 200 GB photo library. A `tar.gz` archive of 200 GB would take over an hour to create, consume 200 GB of temporary space during compression (or more, if compressed), and produce a monolithic file that's useless for incremental updates. If I upload 10 new photos tomorrow, I'd need to re-tar the entire 200 GB to capture those 10 photos.

`rsync` solves this with incremental synchronization. It compares the source and destination file-by-file, transferring only new or modified files. For an append-heavy workload like photo backup (new photos are added daily, existing photos are never modified), rsync transfers only the delta — typically a few megabytes per day.

I wrote `scripts/sdrive-blob-backup.sh` with these design decisions:

### Bandwidth Limiting

```bash
BWLIMIT="--bwlimit=50000"  # 50 MB/s
```

Without a bandwidth limit, rsync would saturate the USB 3.0 bus during backup, degrading performance for any concurrent photo uploads. 50 MB/s is roughly 12% of the bus's theoretical bandwidth, leaving plenty of headroom for the Ente app to continue uploading photos during backup.

### Checksum Verification

```bash
rsync --checksum
```

By default, rsync uses file modification time and size to determine whether a file has changed. The `--checksum` flag forces rsync to compute and compare checksums for every file, guaranteeing data integrity. This is slower (rsync reads every byte of every file on both sides), but for a backup system protecting irreplaceable photos, correctness is worth the cost.

### Deletion Mirroring

```bash
rsync --delete
```

When a user deletes a photo from the Ente app, the encrypted blob is removed from Garage. The `--delete` flag ensures the backup also removes deleted blobs, keeping the backup an exact mirror of the live data. Without this, the backup would grow monotonically, eventually exceeding the backup drive's capacity with data the user intentionally deleted.

### Exit Code 24 Handling

rsync returns exit code 24 when "some files vanished before they could be transferred." This happens when Garage is actively writing during the backup — a block file might be created after rsync scanned the directory but before it transferred the file, or a temporary write might complete and be renamed. Exit 24 is expected and safe; the vanished files will be caught by the next backup run.

## Testing the Blob Backup

I connected a second USB drive to the board (a 128 GB flash drive for testing) and ran the backup:

```bash
root@sdrive:~# mkdir -p /mnt/backup-test
root@sdrive:~# mount /dev/sdb1 /mnt/backup-test

root@sdrive:~# ./scripts/sdrive-blob-backup.sh /mnt/backup-test/garage-data/
======================================================================
 sdrive — Blob Backup (rsync incremental)
 2026-09-21 14:22:18 IST
======================================================================
Source:      /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
Destination: /mnt/backup-test/garage-data/

Source: 3.8G across 5330 block files

sending incremental file list
2f/e8/2fe8a1b3c4d5e6f7...
7a/91/7a91c2d3e4f5a6b7...
...

Number of files: 5,330
Number of created files: 5,330
Number of deleted files: 0
Total file size: 4,127,195,136 bytes
Total transferred file size: 4,127,195,136 bytes

[OK] Blob backup completed in 94 seconds.
Destination: 3.8G across 5330 block files
======================================================================
```

3.8 GB transferred in 94 seconds = 41.4 MB/s effective throughput (capped by the bandwidth limit of 50 MB/s and the flash drive's write speed). The initial sync is always the largest because every file is new. Subsequent runs will only transfer the delta.

I then uploaded 5 new photos to the appliance and ran the backup again:

```bash
root@sdrive:~# ./scripts/sdrive-blob-backup.sh /mnt/backup-test/garage-data/
...
Number of files: 5,355
Number of created files: 25
Number of deleted files: 0
Total file size: 4,148,372,480 bytes
Total transferred file size: 21,177,344 bytes

[OK] Blob backup completed in 4 seconds.
```

25 new files (5 photos × 5 objects each), 20 MB transferred, 4 seconds. The incremental backup works exactly as designed — only the new photos were synced. For a daily backup of a typical family's photo uploads (10–20 photos per day), the nightly rsync would complete in under 10 seconds.

## Dry Run Mode

I tested the dry-run mode to verify it doesn't modify the destination:

```bash
root@sdrive:~# ./scripts/sdrive-blob-backup.sh --dry-run /mnt/backup-test/garage-data/
...
Mode: DRY RUN (no changes will be written)
...
Number of created files: 0
Number of deleted files: 0
[OK] Blob backup completed in 2 seconds.
```

Dry run computes the diff without writing anything. Useful for previewing the backup size before running the real sync to a network target over a slow connection.

## The Two-Tier Backup Schedule

With both backup scripts tested, the complete nightly backup schedule is:

```
3:00 AM  →  sdrive-stack-backup.sh   (metadata: ~3 seconds, ~2 MB)
3:30 AM  →  sdrive-blob-backup.sh    (blobs: ~4–94 seconds, delta only)
```

Metadata first, blobs second. The 30-minute gap ensures the metadata backup completes before the blob backup starts, avoiding any I/O contention. Together, they capture the entire state of the appliance: accounts, encryption keys, album structure, AND the actual encrypted photos.

## The Storage Architecture Document

I wrote `docs/storage-architecture.md` as the authoritative reference for how data lives on the appliance. It consolidates everything discovered in Days 26–30 into a single document:

- The 9-step encryption pipeline from phone to disk
- The three storage tiers (metadata, blobs, system) with sizes, growth rates, and backup methods
- The 5-objects-per-photo S3 structure
- Garage's two-level hash-partitioned block layout
- Capacity planning tables (photo count vs storage vs SSD lifetime)
- The complete backup architecture with restore procedure
- All monitoring schedules and alert thresholds
- Performance baselines from the stress tests

This document is the one I'd hand to someone taking over the system. It answers every question about where data lives, how it flows, and what happens when things break.

## Week 04 Status

Five days into the storage week, the position is:

| Component | Status | Confidence |
|---|---|---|
| Encryption pipeline understood | ✅ | High — traced end-to-end with real photos |
| Garage on-disk layout mapped | ✅ | High — empirically verified |
| First upload tested | ✅ | High — single photo, batch, and video |
| Stress tested (500 photos) | ✅ | High — bottlenecks identified and documented |
| Metadata backup automated | ✅ | High — cron running, first backup verified |
| Blob backup automated | ✅ | High — rsync incremental, tested |
| Storage monitoring automated | ✅ | High — 6-hour SMART + capacity checks |
| Storage architecture documented | ✅ | High — authoritative reference complete |

Tomorrow: Week 04 retrospective and the weekly article. Then Week 05 begins — Tailscale and the overlay network that makes the appliance accessible from anywhere.
