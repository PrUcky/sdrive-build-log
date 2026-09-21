# sdrive Storage Architecture

*Reference: weeks/week-04/day-26.md through day-30.md*

This document is the authoritative reference for how data lives on the sdrive appliance: what gets stored where, how it flows from phone to disk, how it's backed up, and how it's monitored.

---

## Data Flow: Phone to Disk

```
Phone (Ente App)
  │ 1. Encrypt photo: XChaCha20-Poly1305 + Argon2id key derivation
  │ 2. POST /files/upload (encrypted blob + encrypted key bundle)
  ▼
Museum (Go Backend, :8080)
  │ 3. Validate JWT → store metadata in PostgreSQL
  │ 4. S3 PUT → encrypted blob to Garage
  ▼
Garage (Rust S3 Engine, :3900)
  │ 5. Blake2 hash → block storage on SSD
  ▼
USB SSD (/mnt/data, ext4, noatime, discard)
```

**Zero-knowledge guarantee:** The server never sees plaintext photos, encryption keys, or passphrases. Compromising the entire board yields only encrypted blobs and encrypted key bundles.

---

## Storage Tiers

### Tier 1: Metadata (Irreplaceable)

| Component | Location | Content | Size (empty) | Growth Rate |
|---|---|---|---|---|
| PostgreSQL | `sdrive-stack_postgres-data` volume | User accounts, album structure, encrypted key bundles, subscription state | 8.4 MB | ~168 KB/photo |
| Garage SQLite | `sdrive-stack_garage-meta` volume | S3 object index, bucket config, API keys | 148 KB | ~300 B/object |
| Museum state | `sdrive-stack_museum-data` volume | Application transient state | 12 KB | Minimal |

**Backup method:** `scripts/sdrive-stack-backup.sh` — nightly tar.gz, 5 copies retained, ~2.3 MB per snapshot.

> **CRITICAL:** If metadata is lost, encrypted photo blobs become permanently unrecoverable. The encryption key bundles stored in PostgreSQL are the ONLY way to decrypt the photos.

### Tier 2: Blob Data (Encrypted Photos)

| Component | Location | Content | Growth Rate |
|---|---|---|---|
| Garage blocks | `sdrive-stack_garage-data` volume | Encrypted photo/video blobs, thumbnails, metadata envelopes | ~4.5 MB/photo |

**Backup method:** `scripts/sdrive-blob-backup.sh` — rsync incremental to external drive or network target.

### Tier 3: System (Replaceable)

| Component | Location | Content |
|---|---|---|
| Docker images | `/mnt/data/docker/` | Container images (~680 MB, re-pullable) |
| Container layers | `/mnt/data/docker/overlay2/` | Runtime state (ephemeral) |
| Monitoring logs | `/var/log/sdrive/` | Cron job output (7-day rotation, ~372 KB/week) |

**Backup method:** None needed. Docker images are pulled from registries. Logs are diagnostic only.

---

## S3 Object Structure (Per Photo)

Each photo uploaded by the Ente app creates **5 S3 objects** in Garage:

| Object | Typical Size | Purpose |
|---|---|---|
| Encrypted original | 2–12 MB | Full-resolution encrypted photo |
| Encrypted thumbnail | 200–400 KB | Gallery preview (encrypted) |
| Metadata envelope | 10–20 KB | Encrypted EXIF, timestamps |
| Key bundle | 2–4 KB | File key encrypted with master key |
| Collection reference | 1–2 KB | Album membership |

**Overhead:** ~6–9% above raw photo size. 100,000 photos = 500,000 S3 objects.

---

## Garage On-Disk Layout

```
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
├── 2f/
│   └── e8/
│       └── 2fe8a1b3c4d5e6f7...  (Blake2 hash-named block)
├── 7a/
│   └── 91/
│       └── 7a91c2d3e4f5a6b7...
└── .../
```

Two-level hash-partitioned directory tree. Prevents any single directory from exceeding ext4's performance cliff (~10,000 entries per directory).

---

## Capacity Planning

### SSD Budget

| Category | Size | Notes |
|---|---|---|
| OS + Docker images | 1.2 GB | Stable |
| PostgreSQL (100K photos) | ~200 MB | Grows with photo count |
| Garage metadata (500K objects) | ~150 MB | Grows with object count |
| **Available for photos** | **~434 GB** | |

### Photo Capacity Estimates

| Usage Pattern | Photos/Year | Storage/Year | Years Until Full |
|---|---|---|---|
| Casual (5/day) | 1,825 | 7.3 GB | 59 |
| Active (20/day) | 7,300 | 29.2 GB | 14.8 |
| Heavy (50/day) | 18,250 | 73 GB | 5.9 |
| Power + video (100/day) | 36,500 | 292 GB | 1.5 |

### Inode Budget

Total inodes: 30.5 million. At 5 objects/photo: supports **6 million photos** before inode exhaustion.

---

## Backup Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    sdrive Backup Tiers                      │
├───────────────────────────────┬──────────────────────────────┤
│  TIER 1: Metadata             │  TIER 2: Blobs               │
│  sdrive-stack-backup.sh       │  sdrive-blob-backup.sh        │
│                               │                               │
│  Method: tar.gz snapshot      │  Method: rsync incremental     │
│  Schedule: 3:00 AM daily      │  Schedule: 3:30 AM daily       │
│  Size: ~2–5 MB                │  Size: mirrors source          │
│  Retention: 5 copies          │  Retention: 1 mirror           │
│  Contains: PG data, SQLite,   │  Contains: encrypted photo     │
│    museum state, key bundles  │    blobs, thumbnails           │
│  Loss impact: CATASTROPHIC    │  Loss impact: re-upload needed │
└───────────────────────────────┴──────────────────────────────┘
```

### Restore Procedure

1. **Metadata restore:** Extract tar.gz snapshots back to Docker volumes
2. **Blob restore:** rsync from backup to `garage-data` volume
3. **Re-initialize Garage layout:** `scripts/garage-init-layout.sh` (if cluster state lost)
4. **Restart stack:** `docker compose up -d`
5. **Verify:** Check museum health, test photo download from app

---

## Monitoring

| Check | Frequency | Script | Alert Threshold |
|---|---|---|---|
| Container health | Every 15 min | `sdrive-container-health.sh` | Any container unhealthy |
| Golden Signals | Hourly | `sdrive-golden-signals.sh` | Memory > 80%, load > 3.0 |
| Storage capacity | Every 6 hours | `sdrive-storage-monitor.sh` | >70% warn, >85% crit, >95% fatal |
| SMART health | Every 6 hours | `sdrive-storage-monitor.sh` | Reallocated sectors > 0 |
| Backup freshness | Every 6 hours | `sdrive-storage-monitor.sh` | Latest backup > 48h old |
| Docker cleanup | Weekly (Sun) | `docker system prune` | — |

---

## Performance Baselines (Week 04)

| Metric | Value | Source |
|---|---|---|
| Single photo upload | ~0.5s (4.2 MB JPEG over Gigabit LAN) | Day 27 |
| Sustained upload throughput | 6.5–8.2 MB/s | Day 28 stress test |
| Bottleneck #1 | Garage SQLite WAL serialization | Day 28 |
| Bottleneck #2 | Museum in-memory blob buffering | Day 28 (4K video concern) |
| Encryption overhead | 6–9% above raw photo size | Day 27 |
| I/O latency (SSD writes) | 0.42 ms average | Day 27 |
| SSD utilization during burst | 2–3% | Day 27–28 |
| Cold start to all healthy | ~30 seconds | Day 24 |
| Metadata backup size | 2.3 MB (fresh, 1 user) | Day 23 |
| TRIM granularity | 4 KB (matches ext4 block size) | Day 26 |
| SSD write endurance used | 0.0003% | Day 26 |
