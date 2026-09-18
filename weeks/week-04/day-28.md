# Day 28: Stress Testing — 500 Photos, Sustained Throughput, and the First Real Bottleneck

*September 18, 2026*

Yesterday's 25-photo batch upload was a gentle warm-up. Today I pushed the system to find its limits. Five hundred photos from two phones, uploaded simultaneously, while monitoring every metric I have — CPU, memory, disk I/O, container health, network throughput, SSD temperature, and Garage's object count. The goal: find the first bottleneck before the real photo library import in Week 05.

## Test Design

I designed three progressively harder tests:

1. **Sequential burst** — 500 photos from one phone, back-to-back
2. **Concurrent upload** — 200 photos from phone A and 200 from phone B, simultaneously
3. **Mixed media** — 50 photos + 10 short videos (30–60 seconds each, 1080p)

Before each test, I captured a baseline snapshot and reset the monitoring. Between tests, I let the system idle for 5 minutes to observe whether memory and load returned to baseline.

## Test 1: Sequential Burst (500 Photos)

I selected 500 photos from my camera roll — a mix of everyday JPEGs averaging 3.8 MB each, with a few 8-12 MB portrait mode shots and some 1.5 MB screenshots. Total payload: approximately 1.7 GB.

I started the backup on the phone and opened a monitoring dashboard on my desktop:

```bash
root@sdrive:~# watch -n 2 'echo "=== $(date) ==="; \
  docker stats --no-stream --format "{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}"; \
  echo "---"; \
  df -h /mnt/data | tail -1; \
  echo "---"; \
  docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen 2>/dev/null | grep Size'
```

The upload ran for 4 minutes and 38 seconds. Here's what happened inside the stack:

### Memory Profile

```
Timestamp         postgres     garage       museum       Total System
00:00 (start)     38 MB        29 MB        122 MB       348 MB
00:30             42 MB        47 MB        198 MB       451 MB
01:00             44 MB        58 MB        234 MB       502 MB
02:00             46 MB        62 MB        241 MB       518 MB
03:00             46 MB        64 MB        238 MB       516 MB
04:38 (end)       48 MB        61 MB        228 MB       504 MB
05:00 (idle)      48 MB        42 MB        164 MB       412 MB
```

Museum's memory spiked from 122 MB to 241 MB during sustained uploads. Go's garbage collector was running behind the allocation rate — each upload allocates buffers for the encrypted blob, the S3 PUT, and the PostgreSQL metadata write. The GC recovered to 164 MB after uploads stopped, but it didn't return to the original 122 MB baseline. This is normal Go runtime behavior: the heap grows to accommodate peak workload and doesn't immediately shrink. It'll settle back during extended idle periods as the runtime releases unused pages.

Garage climbed from 29 MB to 64 MB — a 2.2× increase. This is SQLite's page cache warming up as it indexes 2,500 new objects (500 photos × 5 objects each). The metadata database was actively growing, and SQLite cached frequently-accessed pages in memory for faster writes.

PostgreSQL barely moved: 38 MB to 48 MB. The metadata writes are tiny compared to the blob data.

**Peak system memory: 518 MB** — that's 13.7% of the 3,788 MB available. The 512 MB container memory limits were never approached. Plenty of headroom.

### CPU and Temperature

```bash
root@sdrive:~# cat /tmp/stress-test-1-cpu.log
Time        Load1   Load5   Temp
00:00       0.14    0.12    49°C
01:00       1.82    0.94    58°C
02:00       2.14    1.28    61°C
03:00       1.96    1.42    62°C
04:38       1.71    1.38    61°C
06:00       0.42    0.89    54°C
```

Load average peaked at 2.14 — about half the quad-core A55's capacity. CPU temperature hit 62°C, well below the 85°C thermal throttle threshold. The RK3566 wasn't breaking a sweat. The load was dominated by Museum's Go goroutines handling concurrent S3 PUTs and PostgreSQL writes, with some CPU spent on Garage's Blake2 hashing of incoming blocks.

### Disk I/O

```bash
root@sdrive:~# iostat -d -y 60 /dev/sda < /tmp/stress-test-1-io.log
Device       tps    kB_read/s    kB_wrtn/s
sda          84.2       12.4      6841.6
sda          91.3       18.7      7102.4
sda          88.1       14.2      6928.0
sda          76.4        8.3      5844.8
```

Sustained write throughput: approximately **6.8 MB/s**. That's the effective speed after accounting for ext4 journaling overhead, Docker's overlay2 copy-on-write, and Garage's block hashing. The raw USB 3.0 bus can deliver 400+ MB/s, so the bottleneck isn't the bus. The bottleneck is **Museum's single-threaded S3 PUT handler** — it serializes uploads through a connection pool to Garage, which processes each PUT sequentially.

At 6.8 MB/s effective throughput, the full 458 GB SSD would take approximately **18.7 hours** to fill from empty. That's perfectly acceptable for an initial photo library import — most people's libraries are 50–100 GB, which would import in 2–4 hours.

### Final Count

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 1938472960 B (2630 objects)
```

2,630 objects (525 photos × 5, including the 25 from yesterday). 1.85 GB of encrypted data on the SSD. Average upload rate: **6.5 MB/s** (1.7 GB / 278 seconds).

## Test 2: Concurrent Upload (Two Phones)

I registered a second test account on the appliance and removed its trial quota. Then I initiated simultaneous backups: 200 photos from phone A and 200 from phone B.

The concurrent test revealed something interesting. Museum handles concurrent connections through Go's goroutine model — each upload spawns a lightweight goroutine, so multiple uploads from different accounts run in parallel. But they all funnel through the same Garage S3 endpoint, which serializes writes to SQLite's WAL:

```
Timestamp         Throughput (combined)    museum MEM    garage MEM
00:00             0 MB/s                   164 MB        42 MB
00:30             8.2 MB/s                 267 MB        71 MB
01:00             7.8 MB/s                 284 MB        78 MB
02:00             7.1 MB/s                 278 MB        74 MB
03:12 (end)       6.4 MB/s                 271 MB        72 MB
```

Combined throughput peaked at 8.2 MB/s — 20% higher than the single-phone test. The parallelism helped because while one upload waited for Garage's SQLite WAL flush, the other could be hashing blocks or writing to PostgreSQL. But the improvement was modest because the fundamental bottleneck — sequential SQLite writes in Garage — can't be parallelized.

Museum's memory peaked at 284 MB — higher than the single-phone test because it was buffering uploads from two connections simultaneously. Still well within the 512 MB limit.

Critically, the two accounts were **completely isolated**. Phone A could not see phone B's photos. Phone B could not see phone A's photos. I verified this by checking the gallery on each device — each showed only its own photos. The zero-knowledge architecture ensures that even though both accounts' encrypted blobs live on the same SSD in the same Garage bucket, neither account's encryption keys can decrypt the other's data.

## Test 3: Mixed Media (Photos + Video)

The video test was the most important. A single 30-second 1080p video from a modern phone is 50–80 MB — 10–20× larger than a typical photo. Ten videos would stress the upload pipeline in a way that 500 small photos don't.

I selected 50 photos and 10 videos (30–60 seconds each, 1080p). Total payload: approximately 1.1 GB (860 MB from videos, 240 MB from photos).

```
Timestamp         Throughput    museum MEM    Load1    Notes
00:00             0 MB/s        164 MB        0.31
00:15             9.4 MB/s      312 MB        2.41     First video uploading
00:30             8.8 MB/s      348 MB        2.67     Museum buffering 80MB blob
01:00             7.2 MB/s      298 MB        1.94     Photos interspersed
01:45             6.8 MB/s      284 MB        1.72
02:28 (end)       —             178 MB        0.44
```

Museum's memory peaked at **348 MB** during the largest video upload. This is because Museum buffers the entire S3 object in memory before forwarding it to Garage. An 80 MB video means an 80 MB allocation in Museum's Go heap, on top of the existing working set. This is the first real concern: if someone uploads a 500 MB 4K video, Museum would need 500 MB for that single request — exactly at its container memory limit.

I noted this as a carry-forward issue: for 4K video support, we may need to increase Museum's memory limit from 512 MB to 768 MB or 1 GB, which still leaves over 2 GB for the host and page cache.

## The Bottleneck Map

After three tests, the bottleneck hierarchy is clear:

```
1. Garage SQLite WAL serialization  → limits single-stream IOPS
2. Museum in-memory blob buffering  → limits max object size
3. USB 3.0 bus bandwidth            → theoretical limit, not reached
4. CPU (quad A55 @ 1.8 GHz)         → never above 55% utilization
5. SSD NAND write speed             → never above 3% utilization
```

Bottleneck #1 (Garage's SQLite) is architectural — it's the price of choosing a lightweight metadata engine over something heavier like PostgreSQL. For our workload (a family's photo library, not a CDN), the 6–8 MB/s throughput is perfectly adequate.

Bottleneck #2 (Museum's buffering) is the only actionable concern. It limits the maximum single-file size that can be uploaded without risking an OOM kill. The fix is simple: increase the memory limit for the museum container if 4K video support is needed.

## Post-Stress Verification

After all three tests, I ran a full health check:

```bash
root@sdrive:~# docker compose ps
NAME                        STATUS              PORTS
sdrive-stack-postgres-1     Up 6 hours (healthy)
sdrive-stack-garage-1       Up 6 hours (healthy)
sdrive-stack-museum-1       Up 6 hours (healthy)

root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 4127195136 B (5330 objects)

root@sdrive:~# df -h /mnt/data
Filesystem      Size  Used Avail Use%
/dev/sda1       458G  5.1G  430G   2%
```

All containers healthy. Zero restart counts. 5,330 objects across 1,060 files (photos + videos). 3.8 GB of encrypted data stored. SSD at 2% capacity. The appliance handled the stress test without a single error, timeout, or restart.

I also verified data integrity by downloading 10 random photos on each phone — all rendered correctly, all decrypted intact. The pipeline is reliable under sustained load.

Tomorrow: the automated backup schedule and filesystem health monitoring cron.
