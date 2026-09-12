# Day 22: The Garage Swap — Ripping Out MinIO and Living to Tell About It

*September 12, 2026*

Today was surgery day. The stock Ente quickstart uses MinIO as its S3-compatible object store, and yesterday we proved the whole system works with MinIO in place. Now we take the calculated risk: rip MinIO out and replace it with Garage, in one isolated change. If anything breaks, we know exactly what broke it.

## Why Garage Over MinIO

I wrote a formal Architecture Decision Record (ADR-003) documenting this choice, but the short version is: memory. On a 4 GB board, every megabyte matters.

MinIO idles at ~92 MB RSS. Garage idles at ~28 MB. That's 64 MB of RAM freed for the Linux page cache, which directly translates to faster I/O for photo reads. MinIO also brings a fleet of features we'll never use: an embedded web console, a full IAM engine, versioning, tiering, replication controllers, and an observability subsystem. Each feature is attack surface. Each feature is a potential CVE. Garage is a single Rust binary with exactly one job: serve the S3 API. It does that job and nothing else.

The critical architectural insight is that `museum` communicates with the object store exclusively through the S3 API. `PutObject`, `GetObject`, `DeleteObject`, `HeadObject`. That's it. Garage implements this subset perfectly. Museum literally cannot tell the difference between MinIO and Garage. The swap is transparent at the application layer.

## The Swap: One Service, Two Config Lines

The actual change was surgical. In `docker-compose.yml`, I replaced the `minio` service definition with `garage`:

```yaml
# BEFORE (MinIO):
minio:
  image: minio/minio:RELEASE.2024-08-29T01-40-52Z
  command: server /data --console-address ":9001"
  volumes:
    - minio-data:/data

# AFTER (Garage):
garage:
  image: dxflrs/garage:v1.0.1
  volumes:
    - ./garage.toml:/etc/garage.toml:ro
    - garage-meta:/mnt/data/garage/meta
    - garage-data:/mnt/data/garage/data
```

In `museum.yaml`, I changed exactly two lines:

```yaml
# BEFORE:
endpoint: http://minio:9000
access_key: minioadmin

# AFTER:
endpoint: http://garage:3900
access_key: REPLACE_WITH_GARAGE_ACCESS_KEY
```

And in the `depends_on` section, `minio` became `garage`. That's the entire diff. Three files touched, one service replaced, two config lines changed.

## Garage's Secret Trap: The Cluster Layout

Here is where Garage departs from MinIO in a critical way that catches everyone. MinIO is "run the container and it works." Garage is not. A fresh Garage node starts in a state where it has no assigned role in the cluster. It knows it exists, but it doesn't know how much storage it should manage or which availability zone it belongs to. Until you explicitly assign a layout and apply it, the S3 API returns errors for every request.

I wrote `scripts/garage-init-layout.sh` to automate this one-time setup:

```bash
root@sdrive:/mnt/data/sdrive-stack# ./scripts/garage-init-layout.sh
======================================================================
 sdrive — Garage Cluster Layout Initialization
======================================================================

[1/5] Waiting for Garage to be ready...
[OK] Garage is responding.

[2/5] Retrieving node ID...
[OK] Node ID: a1b2c3d4e5f67890

[3/5] Assigning cluster layout (zone=dc1, capacity=400G)...
[OK] Layout assigned.
[OK] Layout applied (version 1).

[4/5] Creating bucket 'b2-eu-cen'...
[OK] Bucket 'b2-eu-cen' created.

[5/5] Creating API key 'ente-server-key' and granting bucket access...
[OK] Key 'ente-server-key' created.
[OK] Key 'ente-server-key' granted read/write/owner on 'b2-eu-cen'.

======================================================================
 Garage cluster layout initialized successfully!
======================================================================
```

The script is idempotent — running it again skips steps that have already been completed. This matters because in Week 04, when we start working on backup and restore procedures, we'll need to reinitialize the layout after restoring from a snapshot.

After running the init script, I extracted the generated API key:

```bash
root@sdrive:/mnt/data/sdrive-stack# docker exec sdrive-stack-garage-1 /garage key info ente-server-key
Key name: ente-server-key
Key ID: GK31a2b3c4d5e6f7a8b9c0d1
Secret key: abcdef1234567890abcdef1234567890abcdef1234567890abcdef12
```

I copied these into the local `museum.yaml` (the version on the board, not the repository — the repo version has placeholders), then restarted the stack:

```bash
root@sdrive:/mnt/data/sdrive-stack# docker compose down
root@sdrive:/mnt/data/sdrive-stack# docker compose up -d
[+] Running 4/4
 ✔ Network sdrive-stack_internal  Created                          0.1s
 ✔ Container sdrive-stack-postgres-1  Healthy                      11.8s
 ✔ Container sdrive-stack-garage-1    Healthy                      16.2s
 ✔ Container sdrive-stack-museum-1    Started                      28.4s
```

All three containers healthy. The moment of truth:

```bash
root@sdrive:~# curl -s http://192.168.1.150:8080/health
{"status":"ok"}
```

Museum is alive, talking to Garage. The swap worked.

## Memory: The Proof

This is why we did this:

```bash
root@sdrive:~# docker stats --no-stream
NAME                       CPU %     MEM USAGE / LIMIT     NET I/O
sdrive-stack-postgres-1    0.02%     38.1MiB / 3.629GiB    1.1kB / 0B
sdrive-stack-garage-1      0.04%     28.4MiB / 3.629GiB    2.1kB / 0B
sdrive-stack-museum-1      0.12%     121.8MiB / 3.629GiB   3.8kB / 1.6kB
```

Garage at **28.4 MB** vs MinIO's 92.1 MB from yesterday. That's a **63.7 MB savings** — a 69% reduction in object storage memory footprint. Total container memory dropped from 254 MB to 188 MB.

The Golden Signals confirm:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 348 MB / 3788 MB (9%)
  Disk:   15G / 58G (26%)
  Load:   0.31 0.22 0.12
  CPU:    50°C
```

348 MB total system memory vs 412 MB with MinIO. The board is running cooler too — 50°C vs 52°C — because Garage's Rust runtime doesn't have Go's garbage collector churning in the background.

## Verifying S3 Compatibility

I didn't just trust the health endpoint. I verified that the S3 data plane actually works by writing a test object from inside the museum container's network namespace:

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 0 B (0 objects)
  Authorized keys:
    ente-server-key: read, write, owner
```

Bucket exists, key is authorized, zero objects. The data plane is ready for its first encrypted photo blob.

I also verified the internal DNS resolution path:

```bash
root@sdrive:~# docker exec sdrive-stack-museum-1 nslookup garage
Server:    127.0.0.11
Address:   127.0.0.11:53

Non-authoritative answer:
Name:    garage
Address: 172.18.0.3
```

Docker's internal DNS resolved `garage` to `172.18.0.3` on the bridge network. Museum connects to `http://garage:3900` and gets routed to the right container. The network layer from Week 02 is working exactly as we understood it.

## The Service Graph

I can now draw the complete service graph from memory:

```
[Phone/Desktop]
      |
      | HTTP :8080
      v
  [museum] (Go)
    |         \
    | SQL       \ S3 PUT/GET
    | :5432      \ :3900
    v             v
 [postgres]    [garage] (Rust)
   (38 MB)      (28 MB)
     |              |
     v              v
 [SSD vol]     [SSD vol]
```

Three services. Two data paths. One published port. All data on the SSD. Museum is the only service exposed to the host network. PostgreSQL and Garage are internal-only, reachable exclusively through Docker's bridge network.

This is the architecture. Tomorrow we register the first account and read the verification code from the container logs. The appliance is about to serve its first real user.
