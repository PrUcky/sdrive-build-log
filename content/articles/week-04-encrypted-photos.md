# From Zero to 1,060 Encrypted Photos: Stress Testing a Home Backup Appliance

*By Pratyush Chaudhary · September 23, 2026 · 12 min read*

---

## 1. The Question This Week Answered

Last week, the sdrive appliance ran three containers and returned `{"status":"ok"}`. This week, it actually did its job. The question was: what happens when you push a real photo library through an XChaCha20-Poly1305 encryption pipeline, into a Rust S3 engine, on a quad-core ARM64 board with 4 GB of RAM? Does it work? Does it scale? Where does it break?

The answer: it works, it scales to family-size libraries, and it breaks in two places that are both fixable. Here's everything I learned.

---

## 2. The Encryption Pipeline

Every photo travels through nine steps from your phone to the SSD:

1. The Ente app encrypts the photo with XChaCha20-Poly1305
2. The encrypted blob is POSTed to Museum's API
3. Museum validates the JWT authentication token
4. Museum stores the metadata envelope in PostgreSQL
5. Museum PUTs the encrypted blob to Garage via S3
6. Garage hashes the object key and assigns a partition
7. Garage writes Blake2-hashed blocks to the SSD
8. Garage updates its SQLite metadata index
9. Garage returns the S3 ETag to Museum

The server never sees the plaintext. This is the zero-knowledge guarantee: even with root access to the board, all you get are encrypted blobs.

---

## 3. The 5-Objects-Per-Photo Surprise

I expected each photo to create one S3 object. Instead, Ente creates five:

| Object | Size | Purpose |
|---|---|---|
| Encrypted original | 2–12 MB | Full-resolution photo |
| Encrypted thumbnail | 200–400 KB | Gallery preview |
| Metadata envelope | 10–20 KB | Encrypted EXIF data |
| Key bundle | 2–4 KB | File key encrypted with master key |
| Collection reference | 1–2 KB | Album membership |

This separation is architecturally elegant. The app can load a gallery grid by fetching only thumbnails (200 KB each) without downloading the full originals (4+ MB each). On mobile data, this means browsing your backup is fast and cheap.

But it means the object count scales at 5×. A 100,000-photo library creates 500,000 S3 objects in Garage.

---

## 4. The Stress Test

I ran three progressively harder tests:

**Test 1: 500 photos from one phone.** 1.7 GB uploaded in 4 minutes 38 seconds. Sustained throughput: 6.5 MB/s. Memory peaked at 518 MB (13.7% of available RAM). CPU load peaked at 2.14.

**Test 2: Two phones uploading simultaneously.** 400 photos from two accounts. Combined throughput: 8.2 MB/s — 20% better than single-phone. The parallelism helped because Go's goroutines could overlap I/O operations. Critically, the two accounts were completely isolated: neither phone could see the other's photos.

**Test 3: Photos and video.** 50 photos + 10 videos (30–60 seconds each). Museum's memory spiked to 348 MB during an 80 MB video upload. This revealed the first real concern.

---

## 5. Where It Breaks

The stress test revealed two bottlenecks:

**Bottleneck #1: Garage's SQLite WAL.** Every S3 PUT updates Garage's metadata index, and SQLite serializes WAL writes. This caps single-stream throughput at ~6–8 MB/s regardless of SSD or network speed. For a family photo library, this is perfectly fine — a 100 GB library imports in about 4 hours. For a CDN, it would be a problem. But we're not building a CDN.

**Bottleneck #2: Museum's in-memory buffering.** Museum buffers the entire S3 object in memory before forwarding it to Garage. A 4.2 MB photo barely registers. An 80 MB video costs 80 MB of heap. A 500 MB 4K video would push Museum to its 512 MB container memory limit and risk an OOM kill. The fix is simple: increase Museum's memory limit to 768 MB or 1 GB.

---

## 6. The Backup Architecture

A photo backup appliance needs its own backup. The irony isn't lost on me. But the reasoning is sound: the SSD could fail, the board could be stolen, or a software bug could corrupt the database. The backup architecture has two tiers:

**Tier 1: Metadata.** PostgreSQL data, Garage's SQLite index, and Museum's application state. This is 2.3 MB — tiny, but irreplaceable. The encryption key bundles stored in PostgreSQL are the ONLY way to decrypt the photos. If you lose the key bundles, the encrypted blobs become random noise forever. A nightly tar.gz at 3 AM takes 3 seconds and keeps 5 copies.

**Tier 2: Blob data.** The actual encrypted photos. Currently 3.8 GB and growing. An rsync incremental backup at 3:30 AM transfers only new files — typically 20 MB (about 5 new photos) in 4 seconds. The initial sync of the full 3.8 GB took 94 seconds.

The two tiers have opposite risk profiles. Losing Tier 1 is catastrophic (photos are permanently unrecoverable). Losing Tier 2 is expensive (photos need to be re-uploaded from phones) but not fatal. This justifies different backup strategies: multiple retained copies for metadata, a single mirror for blobs.

---

## 7. Automated Monitoring

Five cron jobs now run on the board:

| Frequency | Job | Purpose |
|---|---|---|
| Every 15 min | Container health | Detect crashed containers |
| Hourly | Golden Signals | Capture system health baseline |
| Every 6 hours | Storage monitor | SSD capacity, SMART health, backup freshness |
| Daily 3:00 AM | Metadata backup | Irreplaceable key bundles |
| Weekly Sunday | Docker prune | Clean up unused images/containers |

The total monitoring footprint is 372 KB per week. The computational cost is unmeasurable. Every failure mode now has a bounded detection time.

---

## 8. The Numbers

| Metric | Week 03 (Empty) | Week 04 (With Data) |
|---|---|---|
| Total system memory | 348 MB (9%) | 356–518 MB (9–14%) |
| SSD used | 1.2 GB (0.3%) | 5.1 GB (1.1%) |
| S3 objects | 0 | 5,330 |
| Photos stored | 0 | 1,060 |
| Upload throughput | untested | 6.5–8.2 MB/s |
| Container restart count | 0 | 0 |
| Automated cron jobs | 0 | 5 |
| Backup coverage | none | metadata + blobs |
| Documentation pages | 7 | 10 |
| Scripts | 17 | 19 |

---

## 9. What's Next

The appliance works on the local network. The phone connects to `192.168.1.150:8080` and backs up photos over Gigabit Ethernet. But the moment you leave the house, the backup stops. Week 05 introduces Tailscale — a WireGuard-based overlay network that makes the board reachable from anywhere, through CGNAT, through hotel WiFi, through mobile data. That's when the appliance becomes truly useful: continuous backup, anywhere, without exposing a single port to the public internet.

---

*This article is part of the **`sdrive` Build Log** — a 12-week public engineering series documenting the ground-up development of an end-to-end encrypted home photo backup appliance. Track the daily commits on GitHub: [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
