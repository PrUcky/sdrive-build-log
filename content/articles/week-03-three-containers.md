# Three Containers on a 4 GB Board: Building a Photo Backup Server from Docker Compose to First Login

*By Pratyush Chaudhary · September 15, 2026 · 14 min read*

---

## 1. The Goal: A Complete Application Stack on a Single-Board Computer

Two weeks ago, the Radxa ROCK 3C was a hardened Linux box with excellent network diagnostics but no application workload. This week, it became a photo backup server. Three containerized services — PostgreSQL for metadata, Garage for S3-compatible object storage, and Ente's Museum backend for the API — now run on a quad-core ARM64 board with 4 GB of RAM, serving encrypted photo backups to a mobile app over the local network.

This article documents the journey from `docker compose up` to first login, including the MinIO-to-Garage swap that saved 64 MB of RAM, the container hardening that prevents cascading failures, and the trial quota trap that silently kills photo imports if you don't know to disarm it.

---

## 2. Storage First: Why the SSD Mount Comes Before Docker

The ROCK 3C boots from a 64 GB microSD card. MicroSD cards use consumer-grade NAND flash with minimal wear-leveling logic. A container runtime writing image layers, database WAL files, and S3 object blobs will exhaust the card's write endurance within months.

Before installing Docker, I connected a 500 GB SATA SSD via USB 3.0 and mounted it at `/mnt/data`:

```bash
parted /dev/sda mklabel gpt
parted /dev/sda mkpart primary ext4 0% 100%
mkfs.ext4 -L sdrive-data /dev/sda1
echo 'UUID=... /mnt/data ext4 defaults,noatime,discard 0 2' >> /etc/fstab
```

The `noatime` flag eliminates unnecessary write amplification by skipping access timestamp updates. The `discard` flag enables continuous TRIM, allowing the SSD controller to optimize its internal garbage collection. Both settings are critical for flash media longevity.

Docker's `data-root` then points at the SSD:

```json
{
  "data-root": "/mnt/data/docker",
  "dns": ["1.1.1.1", "8.8.8.8", "192.168.1.1"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Three settings in this `daemon.json` prevent the three most common embedded Docker failures:

1. **`data-root`** moves everything off the SD card
2. **`dns`** bypasses `systemd-resolved`'s stub listener at `127.0.0.53`, which containers can't reach
3. **`log-opts`** caps each container's logs at 30 MB total, preventing disk exhaustion from log floods

---

## 3. The Stock Baseline: Proving the System Works Before Changing It

The Ente quickstart uses MinIO as its S3 backend. Rather than immediately swapping in Garage, I brought up the stock composition first: PostgreSQL + MinIO + Museum. Three containers, all healthy, `{"status":"ok"}` from the health endpoint.

This baseline serves a critical engineering purpose. When you change two things at once and something breaks, you don't know which change caused the break. By proving the stock quickstart works first and then swapping MinIO for Garage as an isolated change, any failure is immediately attributable to the swap itself.

The baseline also established resource numbers:

| Container | Memory (MinIO baseline) |
|---|---|
| PostgreSQL | 38 MB |
| MinIO | 92 MB |
| Museum | 124 MB |
| **Total** | **254 MB** |

---

## 4. The Garage Swap: 69% Less Memory for the Same API

Garage is a lightweight, Rust-based, S3-compatible object storage engine. Museum communicates with the object store exclusively through a narrow S3 API surface: `PutObject`, `GetObject`, `DeleteObject`, `HeadObject`. Both MinIO and Garage implement this subset fully. Museum literally cannot tell the difference.

The swap touched three files:
- `docker-compose.yml`: replaced the `minio` service with `garage`
- `museum.yaml`: changed the S3 endpoint from `http://minio:9000` to `http://garage:3900`
- `garage.toml`: new configuration for Garage's single-node deployment

Post-swap resource numbers:

| Container | Memory (Garage) | Change |
|---|---|---|
| PostgreSQL | 38 MB | — |
| Garage | 28 MB | **−64 MB (−69%)** |
| Museum | 122 MB | −2 MB |
| **Total** | **188 MB** | **−66 MB** |

On a 4 GB board, 66 MB freed means more page cache for photo I/O. It's the difference between comfortable headroom and eventual memory pressure when the photo library grows.

But Garage has one trap that MinIO doesn't: **cluster layout initialization**. A fresh Garage node has no assigned role. The S3 API returns errors for every request until you explicitly assign a layout:

```bash
garage layout assign -z dc1 -c 400G <node-id>
garage layout apply --version 1
garage bucket create b2-eu-cen
garage key create ente-server-key
garage bucket allow --read --write --owner b2-eu-cen --key ente-server-key
```

I automated this in `scripts/garage-init-layout.sh` — an idempotent script that handles the entire initialization safely.

---

## 5. Container Networking: Why `localhost` Lies to You

Inside a Docker container, `localhost` means the container itself, not the host. This is the single most confusing aspect of container networking for anyone coming from traditional server administration.

Docker creates a virtual bridge network (`172.18.0.0/16`) with its own embedded DNS server. Containers reach each other by service name:

```yaml
# In museum.yaml:
db:
  host: postgres    # ← Docker DNS resolves to 172.18.0.2
  port: 5432
s3:
  endpoint: http://garage:3900  # ← Docker DNS resolves to 172.18.0.3
```

The DNS resolution path is: container process → Docker's embedded DNS at `127.0.0.11` → intercepts service names → returns bridge IP. External names (like `ente.io`) fall through to the upstream resolvers configured in `daemon.json`.

Only Museum publishes a port to the host network (`8080:8080`). PostgreSQL and Garage have zero host-facing ports — they are unreachable from outside Docker's bridge. This is network isolation by default.

---

## 6. The Trial Trap: The Quota That Kills Imports

This is the trap the roadmap warned about.

A fresh self-hosted Ente account starts with a trial storage quota — typically around 1 GB. During initial testing, everything seems fine. A few test photos upload successfully. But when you try to import a real photo library, the upload silently fails partway through with an error that looks like a network timeout, an S3 write failure, or a Garage disk issue.

It's none of those. It's a storage quota. The fix:

```yaml
# In museum.yaml:
internal:
  admins:
    - 1847291  # your numeric user ID
```

```bash
docker compose restart museum
museum admin update-subscription --no-limit --user-id 1847291
```

After this, `storage_limit = -1` in the database: unlimited. Skip this step, and you'll spend a day debugging a phantom bug in Week 05.

---

## 7. Hardening: Containing the Blast Radius

Containers share a single Linux kernel. This is both their strength (near-zero overhead) and their weakness (shared failure domain). Without hardening, a single container can exhaust all 4 GB of RAM, triggering the kernel's OOM killer, which might sacrifice an innocent container to free memory.

Five hardening measures contain this blast radius:

### Memory Limits

```yaml
deploy:
  resources:
    limits:
      memory: 512M
```

Postgres: 512 MB. Garage: 256 MB. Museum: 512 MB. Total ceiling: 1,280 MB, leaving 2,508 MB for the host.

### no-new-privileges

```yaml
security_opt:
  - no-new-privileges:true
```

Blocks privilege escalation via `setuid` binaries or capability manipulation inside containers.

### Read-Only Root Filesystem

```yaml
read_only: true
tmpfs:
  - /tmp:size=64M
```

Garage and Museum run with read-only root filesystems. If an attacker achieves code execution, they cannot persist a backdoor. Transient writes go to a size-capped tmpfs.

### Log Rotation

Global 10 MB × 3 cap per container. Maximum 90 MB of logs for the entire stack. Unbounded logs are the #1 cause of disk exhaustion in long-running embedded deployments.

### Healthcheck-Gated Startup

Museum doesn't start until both Postgres and Garage report healthy. This eliminates the startup race condition where Museum crashes because the database isn't ready, restarts, crashes again, and loops.

---

## 8. The Failure Lab: Killing Services on Purpose

I systematically killed each service and observed the cascade:

| Service Killed | Impact | Recovery Time |
|---|---|---|
| PostgreSQL | Auth fails, metadata unavailable, cached photos still serve | ~3s restart + ~10s reconnect |
| Garage | Uploads/downloads fail, metadata still works | ~3s restart, immediate resume |
| Museum | App loses API entirely, all data safe | ~5s restart |
| All three (power cut) | Full outage, restart in dependency order | ~30s to all healthy |

The critical insight: **data always survives**. Containers are ephemeral. Volumes persist on the SSD. Docker restarts containers automatically. The worst case is 30 seconds of downtime after a power failure.

---

## 9. The Stack in Numbers

| Metric | Value |
|---|---|
| Total container memory | 188 MB (9% of 3.7 GB) |
| Memory saved vs MinIO | 66 MB (69% reduction in object storage) |
| SSD used | 15 GB / 458 GB (3%) |
| CPU temperature (3 containers) | 49–52°C |
| Cold start to all healthy | ~30 seconds |
| Volume backup size | 2.3 MB (metadata only) |
| Hardening measures applied | 5 (mem limits, no-new-priv, ro-rootfs, log rotation, health gates) |
| Container restart count (5-day run) | 0 (all manual) |
| Docker images total disk | ~680 MB |
| Published host ports | 1 (Museum :8080) |

---

## 10. What’s Next

The appliance serves `{"status":"ok"}` and the phone app connects. But we haven't uploaded a single photo yet. Week 04 addresses storage architecture: how Garage organizes encrypted blobs on the SSD, how backups work when the data grows from megabytes to gigabytes, and how to prepare the system for the real photo import in Week 05.

The containers are running. The foundation is solid. Now we fill it with data.

---

*This article is part of the **`sdrive` Build Log** — a 12-week public engineering series documenting the ground-up development of an end-to-end encrypted home photo backup appliance. Track the daily code commits and logs on GitHub: [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
