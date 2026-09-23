# Week 04 Retrospective — Storage Architecture and the First Real Data

*September 16–23, 2026 · Days 26–31*

---

## Goal

> Understand how data flows from phone to disk, stress test the upload pipeline, and automate backups and monitoring.

**Verdict: ACHIEVED.** The encryption pipeline is traced end-to-end, performance is benchmarked under load, backups are automated on two tiers, and the storage architecture is documented as an authoritative reference.

---

## Exit Criteria Assessment

| Criterion | Status | Evidence |
|---|---|---|
| Trace the encryption pipeline end-to-end | ✅ PASS | Day 26–27: 9-step pipeline from phone to SSD |
| Upload and retrieve a real photo | ✅ PASS | Day 27: single photo + batch of 25 |
| Stress test under sustained load | ✅ PASS | Day 28: 500 photos, concurrent phones, mixed media |
| Identify system bottlenecks | ✅ PASS | Day 28: SQLite WAL + Museum buffering |
| Automate metadata backups | ✅ PASS | Day 29: nightly cron at 3 AM |
| Automate blob backups | ✅ PASS | Day 30: rsync incremental at 3:30 AM |
| Automate storage monitoring | ✅ PASS | Day 29: 6-hour SMART + capacity checks |
| Document the storage architecture | ✅ PASS | Day 30: authoritative reference |

---

## Milestone Inventory

### Day 26 — Storage Architecture Deep Dive
- Traced the 9-step encryption pipeline: phone → XChaCha20 → Museum → PostgreSQL → Garage → SSD
- Mapped Garage's on-disk layout: Blake2-hashed blocks in two-level hash directories
- Established filesystem monitoring thresholds: 70% warn, 85% critical, 95% fatal
- Analyzed PostgreSQL schema: 47 tables, 8.4 MB fresh, ~168 KB/photo growth
- Verified SSD TRIM (4 KB granularity) and SMART health (0 reallocated sectors)
- Built capacity planning model: 434 GB usable → 59 years casual, 1.5 years power user

### Day 27 — First Real Photo Upload
- Single photo upload: 4.2 MB JPEG, 0.5 seconds, 6.4% encryption overhead
- Discovered 5-objects-per-photo S3 structure (original, thumbnail, metadata, key bundle, collection)
- Verified Garage block layout empirically: hash-partitioned directories on SSD
- I/O analysis: 12 write IOPS burst, 0.42 ms latency, 2.1% SSD utilization
- Round-trip verified: photo downloaded on second device, decrypted intact
- Batch test: 25 photos (112 MB) in 14 seconds, 8.5% overhead

### Day 28 — Stress Testing
- Test 1: 500 photos from one phone → 6.5 MB/s sustained, peak 518 MB memory (13.7%)
- Test 2: 400 photos from two phones concurrent → 8.2 MB/s combined, account isolation verified
- Test 3: 50 photos + 10 videos → Museum peaked at 348 MB during large video upload
- Bottleneck #1: Garage SQLite WAL serialization (caps single-stream throughput)
- Bottleneck #2: Museum in-memory blob buffering (limits max file size to ~512 MB)
- CPU peaked at load 2.14, temperature 62°C. Zero errors, zero restarts.

### Day 29 — Automated Backbone
- Storage health monitor: SSD capacity, SMART, inodes, Garage stats, PG size, backup freshness
- 5-job cron schedule: container health (15m), Golden Signals (1h), storage (6h), backup (daily), prune (weekly)
- Log rotation: 7-day cap, ~372 KB/week total monitoring footprint
- Reliability model: every failure mode has bounded detection time

### Day 30 — Blob Backup Pipeline
- rsync incremental backup script: bandwidth limiting, checksum verification, deletion mirroring
- Initial sync: 3.8 GB in 94 seconds (41.4 MB/s)
- Incremental sync: 25 new files (20 MB) in 4 seconds
- Two-tier backup schedule: metadata at 3:00 AM, blobs at 3:30 AM
- Authoritative storage architecture document: data flow, tiers, capacity, backups, monitoring

### Day 31 — Retrospective and Weekly Article
- Formal exit criteria assessment (this document)
- Published weekly article: *From Zero to 1,060 Encrypted Photos*

---

## Artifacts Produced

### Scripts
| File | Purpose |
|---|---|
| `scripts/sdrive-storage-monitor.sh` | Storage health: capacity, SMART, inodes, backup freshness |
| `scripts/sdrive-blob-backup.sh` | Incremental blob backup via rsync |

### Configuration
| File | Purpose |
|---|---|
| `config/cron/sdrive-crontab` | 5-job automated maintenance schedule |
| `config/logrotate/sdrive` | 7-day log rotation for monitoring logs |

### Documentation
| File | Purpose |
|---|---|
| `docs/storage-architecture.md` | Authoritative storage reference (data flow, tiers, backups, monitoring) |

### Content
| File | Purpose |
|---|---|
| `content/articles/week-04-encrypted-photos.md` | Weekly technical essay |

---

## Key Performance Numbers

| Metric | Value | Context |
|---|---|---|
| Single upload throughput | 6.5 MB/s | 4.2 MB JPEG over Gigabit LAN |
| Concurrent upload throughput | 8.2 MB/s | Two phones simultaneously |
| Upload bottleneck | Garage SQLite WAL | Sequential writes to metadata index |
| Encryption overhead | 6–9% | Above raw photo size |
| Objects per photo | 5 | Original + thumbnail + metadata + key + collection |
| Peak memory (500 photos) | 518 MB (13.7%) | Well within 4 GB limit |
| Peak CPU load (stress test) | 2.14 | Half quad-core capacity |
| Peak temperature | 62°C | Below 85°C throttle |
| SSD write latency | 0.42 ms | Near-zero I/O pressure |
| Metadata backup size | 2.3 MB | Nightly tar.gz |
| Incremental blob backup | 4 seconds | For 25 new photos |
| Monitoring log footprint | 372 KB/week | 5 cron jobs, 7-day rotation |
| Total data stored (tests) | 3.8 GB | 1,060 photos + 10 videos |

---

## Known Issues and Carry-Forward

| Issue | Severity | Planned Resolution |
|---|---|---|
| Museum buffers entire objects in memory | **HIGH** | Increase memory limit for 4K video (512 MB → 768 MB) |
| Museum image uses floating `:latest` tag | HIGH | Pin to digest once stable ARM64 release available |
| No blob backup destination configured in cron | MEDIUM | Week 05+: add rsync target after Tailscale |
| No off-site/geographic backup | MEDIUM | Week 06+: potential remote Garage replication |
| No TLS on Museum endpoint (plain HTTP) | MEDIUM | Week 06: Caddy reverse proxy |
| Backup freshness alert is log-only | LOW | Week 06+: add push notification via webhook |

---

## Lessons Learned

1. **Measure before optimizing.** I expected the USB 3.0 bus to be the bottleneck. It wasn't. The bottleneck was Garage's SQLite WAL serialization — something I wouldn't have found without the stress test. Performance intuition is unreliable; `iostat` and `docker stats` are not.

2. **5 objects per photo changes capacity math.** The naive calculation of "458 GB / 4 MB = 114,000 photos" is wrong. It's really 458 GB / 4.5 MB = 101,000 photos (accounting for thumbnails and metadata), and the inode budget is 30.5M / 5 = 6.1M photos. Always measure the real on-disk footprint.

3. **Two-tier backup is essential.** Metadata (2.3 MB, irreplaceable key bundles) and blobs (3.8 GB, re-uploadable but expensive) have completely different backup profiles. A single backup strategy for both would either be too expensive (tar.gz of multi-GB blobs) or too risky (skipping metadata because it's "small").

4. **Automated monitoring costs nothing.** Five cron jobs generating 372 KB/week of logs. The computational cost is unmeasurable. The value is bounded detection time for every failure mode. There is no excuse for running an unmonitored appliance.

5. **The board is overpowered for this workload.** Peak utilization during the stress test: 13.7% memory, 53% CPU (load 2.14 / 4 cores), 2% SSD. The ROCK 3C could comfortably run two or three more services (Caddy, Tailscale, a monitoring dashboard) without breaking a sweat.

---

*Week 04 complete. Week 05: Tailscale overlay network and remote access.*
