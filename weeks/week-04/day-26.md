# Day 26: Storage Architecture — How Encrypted Photos Live on Disk

*September 16, 2026*

Week 04 begins. The stack is running — PostgreSQL, Garage, Museum, all healthy on the ROCK 3C with the first user account registered and unlimited storage granted. But we haven't uploaded a single photo yet. Before we do, I need to understand exactly how data flows from the phone to the disk, how Garage organizes encrypted blobs on the SSD, and what happens to the filesystem as the photo library grows from empty to tens of gigabytes.

Today's question is fundamental: when the Ente app encrypts a photo and uploads it, where does the data actually end up?

## The Encryption Pipeline

The data path starts on the phone. The Ente app performs client-side encryption using XChaCha20-Poly1305 with a 192-bit nonce. The encryption key is derived from the user's passphrase via Argon2id — a memory-hard key derivation function that resists GPU brute-force attacks. The critical architectural point is that **the server never sees the plaintext photo**. It never sees the encryption key. It never sees the passphrase. The server receives an opaque encrypted blob and stores it as-is.

This is the zero-knowledge architecture. Even if someone compromises the ROCK 3C entirely — root access, database dump, SSD removal — they get encrypted blobs and encrypted key bundles. Without the user's passphrase, the photos are unrecoverable. The server is a dumb storage pipe.

The upload path through the stack:

```
Phone (Ente App)
  │
  │ 1. Encrypt photo with XChaCha20-Poly1305
  │ 2. POST /files/upload to museum:8080
  │
  ▼
Museum (Go Backend)
  │
  │ 3. Validate JWT auth token
  │ 4. Store metadata envelope in PostgreSQL
  │    (file ID, encrypted filename, timestamps, key bundle)
  │ 5. PUT object to garage:3900 (S3 API)
  │
  ▼
Garage (Rust S3 Engine)
  │
  │ 6. Hash object key → partition assignment
  │ 7. Write data blocks to /mnt/data/garage/data/
  │ 8. Update SQLite metadata index
  │ 9. Return S3 ETag to museum
  │
  ▼
USB SSD (/mnt/data)
  │
  └── Encrypted blob at rest on ext4 filesystem
```

Nine steps from phone to disk. The photo is encrypted before step 1 and never decrypted until it returns to a client device. The entire server-side pipeline handles opaque bytes.

## Garage's On-Disk Layout

I dove into how Garage actually organizes data on the SSD. Garage uses a content-addressable storage model internally. Each S3 object is split into blocks (default 1 MB), and each block is stored as a file named by its Blake2 hash:

```bash
root@sdrive:~# find /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/ -type f | head -5
# (empty — no photos uploaded yet)

root@sdrive:~# du -sh /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
4.0K    /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
```

Empty. 4 KB of directory overhead. But once photos start flowing, this directory will contain thousands of block files organized in a hash-partitioned directory tree. Garage creates a two-level directory hierarchy based on the first characters of the block hash: `ab/cdef1234.../` — this prevents any single directory from containing millions of entries, which would destroy ext4 lookup performance.

The metadata index lives separately in the `garage-meta` volume as a SQLite database:

```bash
root@sdrive:~# du -sh /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/
148K    /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/

root@sdrive:~# find /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/ -name "*.db" -o -name "*.sqlite"
/mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/db.sqlite
```

148 KB for the empty metadata database. SQLite is the right choice here — it's the most tested embedded database on Earth (their test harness exceeds 100% branch coverage), and it handles the access pattern perfectly: infrequent writes (object uploads), frequent reads (object downloads), and crash recovery via its WAL (Write-Ahead Log) journal.

## Filesystem Monitoring

I set up monitoring to track how the SSD usage grows over time. The baseline before any uploads:

```bash
root@sdrive:~# df -h /mnt/data
Filesystem      Size  Used Avail Use%  Mounted on
/dev/sda1       458G  1.2G  434G   1%  /mnt/data

root@sdrive:~# du -sh /mnt/data/docker/
1.2G    /mnt/data/docker/
```

1.2 GB used — that's entirely Docker images and empty volumes. The actual data capacity for photos is approximately 434 GB. At an average of 4 MB per phone photo (mixing 2 MB compressed JPEGs and 10 MB RAW/HEIF files), that's roughly **108,000 photos** before the SSD fills up.

But I don't want to discover the SSD is full when an upload fails. I need proactive monitoring. I wrote a filesystem capacity check into the existing Golden Signals script and set threshold alerts:

```bash
# Capacity thresholds
DISK_WARN=70   # Yellow: start planning expansion
DISK_CRIT=85   # Red: stop non-essential writes, alert immediately
DISK_FATAL=95  # Emergency: risk of filesystem corruption
```

When disk usage crosses 70%, the Golden Signals output will flag it as a warning. At 85%, it becomes critical. At 95%, the appliance should refuse new uploads to prevent ext4 from running out of space — a condition that can cause silent data corruption if the filesystem can't allocate blocks for journal writes.

## PostgreSQL Storage Patterns

The metadata in PostgreSQL grows much more slowly than the blob data in Garage. Each photo's metadata envelope is approximately 2 KB — the encrypted filename, timestamps, encrypted thumbnail reference, encrypted key bundle, and album membership. For 100,000 photos, that's roughly 200 MB of PostgreSQL data.

I checked the current database size:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c \
  "SELECT pg_size_pretty(pg_database_size('ente_db'));"
  8424 kB
```

8.4 MB for the fresh database with one user account and zero photos. That includes system catalogs, the schema Museum created during its first-boot migration, and the subscription records.

I also checked how many tables Museum created:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
  47
```

47 tables. Museum's schema is more complex than I expected. It tracks files, collections (albums), sharing permissions, authentication tokens, key attributes, subscription state, and a variety of server-side metadata. All of it holds encrypted values that only the client can decrypt — the zero-knowledge property is maintained at the schema level.

## Backup Strategy: The Two-Tier Model

The Week 03 backup script (`sdrive-stack-backup.sh`) handles the metadata tier: PostgreSQL data, Garage's SQLite index, and Museum's application state. That's the 2.3 MB backup that contains irreplaceable data — encryption key bundles that, if lost, render all encrypted photos permanently unrecoverable.

But the blob tier — the actual encrypted photos in `garage-data` — needs a different strategy. These files can grow to hundreds of gigabytes, making tar.gz archives impractical. The right approach is incremental synchronization:

```bash
# Concept: rsync the garage data volume to a backup location
rsync -av --delete \
  /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/ \
  /mnt/backup/garage-data/
```

The `--delete` flag ensures the backup mirrors deletions (when users delete photos, the backup should also delete them to reclaim space). The incremental nature of `rsync` means only new or modified blocks are transferred — perfect for the append-heavy workload of a photo backup service.

For now, the backup target would be a second USB drive or a network share. In Week 06, when Tailscale is operational, we could potentially replicate to a remote Garage node for geographic redundancy. But that's a future concern.

## TRIM and Wear Leveling

The SSD's health is critical for long-term reliability. I verified that continuous TRIM is working:

```bash
root@sdrive:~# findmnt -o DISCARD /mnt/data
DISCARD
discard

root@sdrive:~# cat /sys/block/sda/queue/discard_max_bytes
4294966784

root@sdrive:~# cat /sys/block/sda/queue/discard_granularity
4096
```

TRIM is active with a 4 KB granularity — matching the ext4 block size. When files are deleted, the filesystem tells the SSD controller which blocks are no longer in use, allowing the controller to pre-erase them for future writes. This maintains consistent write performance over the SSD's lifetime and prevents the write amplification that degrades untrimmed SSDs.

I also checked the SSD's SMART data for wear indicators:

```bash
root@sdrive:~# smartctl -a /dev/sda | grep -i "wear\|life\|written"
  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
  9 Power_On_Hours          0x0032   099   099   000    Old_age   Always       -       342
241 Total_LBAs_Written      0x0032   099   099   000    Old_age   Always       -       1847291
```

342 power-on hours (the SSD has been running since the ROCK 3C's first boot). Zero reallocated sectors — no bad blocks. 1.8 million LBAs written, which translates to roughly 900 MB of total writes. The SSD's endurance rating is typically 100-300 TBW (Terabytes Written), so we've used approximately 0.0003% of its write life. Even at 10 GB of new photos per day, the SSD would last over 27 years. Storage endurance is not a concern.

## The Capacity Planning Model

| Scenario | Photo Count | Storage Used | SSD Lifetime |
|---|---|---|---|
| Casual user (5 photos/day) | 1,825/year | ~7.3 GB/year | 59 years |
| Active user (20 photos/day) | 7,300/year | ~29.2 GB/year | 14.8 years |
| Heavy user (50 photos/day) | 18,250/year | ~73 GB/year | 5.9 years |
| Power user (100 photos/day + video) | 36,500/year | ~292 GB/year | 1.5 years |

For a typical family use case (two phones, moderate usage), the 458 GB SSD provides roughly 8-10 years of storage at 4 MB average per photo. Video changes the equation dramatically — a single 4K video clip can be 500 MB. The backup strategy needs to account for this.

Tomorrow: testing the upload pipeline end-to-end with a real photo for the first time, measuring the actual I/O patterns, and validating that Garage's on-disk layout matches our expectations.
