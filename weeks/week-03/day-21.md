# Day 21: The Stock Quickstart and the First Signs of Life

*September 11, 2026*

Today the appliance stops being a hardened Linux box and starts being a photo backup server. The roadmap is very specific about the order: bring up the stock Ente quickstart first, completely unmodified, as a known-good baseline. Don't touch the object store. Don't customize the Compose file. Don't optimize anything. Just get it running and prove that the three services — PostgreSQL, MinIO, and `museum` — can communicate over Docker's internal bridge network on this ARM64 board.

I spent the morning writing the `docker-compose.yml` and `museum.yaml` configuration files. Every decision in these files was deliberate, even for a "stock" quickstart.

## The Compose File, Line by Line

Docker Compose is a declarative description of a system. You don't tell it how to start services — you tell it what the system should look like when it's running, and the runtime figures out the sequencing. Our system has three services:

**PostgreSQL 16** is the metadata store. Every user account, every album, every photo's encrypted metadata envelope lives in this database. The actual encrypted photo bytes never touch Postgres — they go to the S3 object store. Postgres holds the control plane: who owns what, what's shared with whom, and the encrypted key bundles that only the client can decrypt.

I pinned the image to `postgres:16-bookworm` with a SHA-256 digest. This is critical for reproducibility. If I run `docker compose up` in three months, I want exactly the same binary, not whatever `16-bookworm` happens to point to by then. Floating tags are a trap — they silently pull new versions that might have breaking changes, different default configurations, or even supply-chain compromises.

The healthcheck runs `pg_isready` every 10 seconds. This isn't just cosmetic — the `museum` service has a `depends_on` condition of `service_healthy`, which means Docker will not start `museum` until PostgreSQL's healthcheck passes. Without this, `museum` would crash on startup because the database isn't ready, then restart, crash again, and loop until the restart backoff timer happens to align with Postgres being available. Healthchecks convert race conditions into ordered startup sequences.

**MinIO** is the stock S3-compatible object store from the Ente quickstart. This is temporary — we will replace it with Garage in a subsequent session. But the roadmap says to bring it up unmodified first, prove the system works, and then swap one component at a time. If the Garage swap breaks something, I'll know it was the swap that broke it, not some other configuration error.

MinIO's healthcheck uses `mc ready local`, which verifies that the S3 API endpoint is accepting connections. Like Postgres, this gates the `museum` startup.

**Museum** is Ente's Go backend. It connects to Postgres for metadata and to the S3 endpoint (MinIO, for now) for encrypted blob storage. It exposes port 8080, which is the API that the Ente phone app communicates with. The `museum.yaml` file provides all the connection details: database credentials, S3 endpoint and keys, JWT signing secret, and server-side key wrapping keys.

The `museum.yaml` file in this repository contains **placeholder secrets only**. Every password, key, and secret is a `REPLACE_WITH_...` marker. The real secrets are generated on the board and never committed to git. This is the privacy guarantee from Day 01: zero secrets in the repository, ever.

## The First `docker compose up`

I copied the compose files to the board and ran the pull:

```bash
root@sdrive:~# cd /mnt/data/sdrive-stack
root@sdrive:/mnt/data/sdrive-stack# docker compose pull
[+] Pulling 3/3
 ✔ postgres Pulled                                               42.3s
 ✔ minio Pulled                                                   38.7s
 ✔ museum Pulled                                                  51.2s
```

Three images. 132 seconds total to pull them over our ISP connection. The ARM64 variants downloaded automatically — Docker's multi-arch manifest system detected the ROCK 3C's `aarch64` architecture and pulled the correct platform images. No cross-compilation, no emulation, no QEMU. Native ARM64 binaries running on native ARM64 silicon.

I generated the real secrets on the board using `openssl`:

```bash
root@sdrive:/mnt/data/sdrive-stack# openssl rand -hex 32  # JWT secret
root@sdrive:/mnt/data/sdrive-stack# openssl rand -hex 32  # encryption key
root@sdrive:/mnt/data/sdrive-stack# openssl rand -hex 32  # hash key  
root@sdrive:/mnt/data/sdrive-stack# openssl rand -base64 24  # postgres password
root@sdrive:/mnt/data/sdrive-stack# openssl rand -base64 24  # minio password
```

I substituted these into the local copies of `museum.yaml` and `docker-compose.yml`, then brought the stack up:

```bash
root@sdrive:/mnt/data/sdrive-stack# docker compose up -d
[+] Running 4/4
 ✔ Network sdrive-stack_internal  Created                          0.1s
 ✔ Container sdrive-stack-postgres-1  Started                      0.8s
 ✔ Container sdrive-stack-minio-1     Started                      0.9s
 ✔ Container sdrive-stack-museum-1    Waiting                      ...
```

Museum waited. It sat in the `Waiting` state while the healthchecks for Postgres and MinIO cycled through their 10-second intervals. After about 30 seconds, both dependencies reported healthy, and museum started:

```bash
[+] Running 4/4
 ✔ Network sdrive-stack_internal  Created                          0.1s
 ✔ Container sdrive-stack-postgres-1  Healthy                      12.3s
 ✔ Container sdrive-stack-minio-1     Healthy                      14.1s
 ✔ Container sdrive-stack-museum-1    Started                      31.2s
```

All three containers running. I checked the health status:

```bash
root@sdrive:/mnt/data/sdrive-stack# docker compose ps
NAME                        STATUS              PORTS
sdrive-stack-postgres-1     Up 2 minutes (healthy)    
sdrive-stack-minio-1        Up 2 minutes (healthy)    
sdrive-stack-museum-1       Up 1 minute (healthy)     0.0.0.0:8080->8080/tcp
```

Three services. All healthy. Museum publishing port 8080 to the host. I hit the health endpoint from my desktop:

```bash
C:\> curl -s http://192.168.1.150:8080/health
{"status":"ok"}
```

That single JSON response represents the culmination of three weeks of work. The packet traveled from my desktop, through the Gigabit switch, into the RTL8211F PHY, through the UFW firewall (rule #2: 8080/tcp from LAN), into Docker's bridge network, through the container's network namespace, into the `museum` Go process, which queried PostgreSQL to verify its own health, and returned `{"status":"ok"}` back through the entire stack in reverse.

I verified the socket audit reflected the new service:

```bash
root@sdrive:~# ss -tulnp | grep 8080
tcp   LISTEN 0      4096   0.0.0.0:8080   0.0.0.0:*   users:(("docker-proxy",pid=8421,fd=4))
```

`docker-proxy` is Docker's userspace port forwarding daemon. It listens on the host's port 8080 and forwards traffic into the container's network namespace. The attack surface has grown by exactly one listener, as expected.

## Container Networking: What `localhost` Means Now

Inside the Docker bridge network, each container gets its own IP address. They can reach each other by service name (Docker's embedded DNS resolves `postgres` to the Postgres container's bridge IP). But `localhost` inside a container means the container itself, not the host. This is why PostgreSQL is configured in `museum.yaml` with `host: postgres` (the Docker service name), not `host: localhost` or `host: 127.0.0.1`.

This is also why we configured `dns` in `daemon.json` yesterday. Without it, containers would try to use the host's `/etc/resolv.conf`, which points to `127.0.0.53` (the `systemd-resolved` stub) — and that address doesn't exist inside the container's network namespace.

I verified internal DNS resolution from inside a container:

```bash
root@sdrive:~# docker exec sdrive-stack-museum-1 nslookup postgres
Server:    1.1.1.1
Address:   1.1.1.1:53

Non-authoritative answer:
Name:    postgres
Address: 172.18.0.2
```

Wait — that's wrong. The DNS query went to Cloudflare (`1.1.1.1`) instead of Docker's internal DNS server (`127.0.0.11`). But it still resolved, because Docker's embedded DNS intercepts queries for service names before they hit the external resolver. The resolution path is: container → Docker DNS (127.0.0.11) → intercepts `postgres` → returns `172.18.0.2`. The `nslookup` output is misleading about which server actually answered, but the result is correct.

## Resource Impact

With the full stack running, I checked the Golden Signals:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 412 MB / 3788 MB (10%)
  Disk:   14G / 58G (24%)
  Load:   0.42 0.28 0.15
  CPU:    52°C
```

Memory jumped from 142 MB (bare system) to 412 MB (with three containers). That's a 270 MB increase — mostly PostgreSQL's shared buffers and museum's Go heap. CPU temperature rose from 47°C to 52°C. Load average is 0.42, which is well within the quad-core A55's capability. We're using 10% of available memory. Plenty of headroom, but the trajectory is clear: each service we add eats roughly 90 MB of RAM. The 4 GB limit on this board means we can run about 30 services before hitting memory pressure. We only need five.

I also checked container-specific resource usage:

```bash
root@sdrive:~# docker stats --no-stream
NAME                       CPU %     MEM USAGE / LIMIT     NET I/O
sdrive-stack-postgres-1    0.02%     38.4MiB / 3.629GiB    1.2kB / 0B
sdrive-stack-minio-1       0.08%     92.1MiB / 3.629GiB    2.4kB / 0B
sdrive-stack-museum-1      0.15%     124.3MiB / 3.629GiB   4.1kB / 1.8kB
```

Museum is the heaviest at 124 MB (Go's garbage collector is generous with heap). MinIO at 92 MB. Postgres is the lightest at 38 MB (it will grow as data arrives). Total container memory: 254 MB. The remaining 158 MB of the 412 MB total is Docker daemon overhead, bridge networking, and page cache.

The stock Ente quickstart is alive on the ROCK 3C. Three containers, all healthy, all communicating over Docker's internal bridge network, all persisting data on the USB SSD via Docker volumes. The phone app can't connect yet — we need to configure the client to point at `192.168.1.150:8080` instead of Ente's cloud servers — but the server side is proven.

Tomorrow we take the first calculated risk: ripping out MinIO and replacing it with Garage, the Rust-based distributed object storage engine that is the heart of the sdrive data plane.
