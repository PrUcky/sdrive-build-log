# Day 24: The Compose Deep-Read and the Container Failure Lab

*September 14, 2026*

Sunday. Six hours today. The stack is running, the first account is registered, storage is unlimited. The roadmap says: "Read the Compose file line by line until every service is understood." That's today's job. Not skimming. Not nodding along. Understanding every directive well enough to explain what would happen if I deleted it.

I printed the `docker-compose.yml` on my desktop and went through it line by line with the stack running on the board, testing every assertion by deliberately breaking things.

## The Version Directive

```yaml
version: "3.8"
```

This specifies the Compose file format version. `3.8` is the latest `3.x` schema, which supports `deploy` resource limits, `healthcheck` configs, and `depends_on` conditions. The version string is actually deprecated in modern Docker Compose V2 (the Go rewrite) — it's ignored entirely. But I keep it for backward compatibility with older documentation and tooling. Removing it changes nothing.

## Service: PostgreSQL

```yaml
image: postgres:16-bookworm@sha256:3d9ed83...
```

The `@sha256:` suffix is a **content-addressable digest**. When Docker pulls this image, it doesn't just match the tag name — it verifies the cryptographic hash of the entire image manifest. If Docker Hub's CDN served a different image (compromised mirror, tag mutation, supply chain attack), the pull would fail with a digest mismatch. This is the strongest possible guarantee that "what I tested today is what runs tomorrow."

I tested this by corrupting the digest:

```bash
root@sdrive:~# docker pull postgres:16-bookworm@sha256:0000000000000000
error pulling image: manifest unknown
```

Clean failure. Docker refused to pull an image that doesn't match the expected hash.

```yaml
restart: unless-stopped
```

This is the restart policy. `unless-stopped` means: restart the container automatically after crashes, Docker daemon restarts, and system reboots — but NOT after a manual `docker compose stop`. The alternatives are:
- `no`: Never restart (dangerous for production)
- `always`: Restart even after manual stops (annoying during maintenance)
- `on-failure`: Restart only on non-zero exit codes (doesn't handle OOM kills)

I tested by killing the Postgres process inside the container:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 kill -9 1
# Container immediately restarted
root@sdrive:~# docker ps --filter name=postgres
STATUS: Up 3 seconds (health: starting)
```

Three seconds. The container died and Docker restarted it before I could type the next command. The healthcheck transitions to `starting`, runs `pg_isready`, and within 10 seconds reports `healthy` again. Museum, which depends on Postgres being healthy, momentarily lost its database connection but retried automatically because Go's `database/sql` package has built-in connection pool recovery.

```yaml
environment:
  POSTGRES_DB: ente_db
  POSTGRES_USER: pguser
  POSTGRES_PASSWORD: REPLACE_WITH_STRONG_PASSWORD
```

These environment variables are read by the official Postgres Docker entrypoint script on first boot ONLY. They create the database and user during initialization. On subsequent startups, the entrypoint detects that the data directory already exists and skips initialization entirely. Changing these variables after first boot does nothing — the database already exists with the original credentials.

```yaml
volumes:
  - postgres-data:/var/lib/postgresql/data
```

This is the named volume mount. The Postgres data directory — WAL files, table data files, pg_xlog, everything — lives in a Docker named volume, which physically resides on the SSD at `/mnt/data/docker/volumes/sdrive-stack_postgres-data/_data/`. The container is ephemeral; the volume is permanent.

I tested by destroying and recreating the container:

```bash
root@sdrive:~# docker compose stop postgres
root@sdrive:~# docker compose rm -f postgres
root@sdrive:~# docker compose up -d postgres
# Postgres came up with all data intact
root@sdrive:~# docker exec sdrive-stack-postgres-1 psql -U pguser -d ente_db -c "SELECT count(*) FROM users;"
 count
-------
     1
```

The user account survived. The container was destroyed and recreated from scratch, but the data persisted in the volume. This is the entire point of separating code (images) from state (volumes).

## Service: Garage

```yaml
read_only: true
tmpfs:
  - /tmp:size=16M
```

The read-only rootfs is a security hardening measure, but it's also an operational diagnostic. If Garage tries to write to an unexpected location — a bug, a misconfiguration, a compromised dependency — it will get a clean `EROFS` (Read-only file system) error instead of silently corrupting state. The `tmpfs` provides a small writable scratch space for temporary files.

I verified by trying to write inside the container:

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 touch /test
touch: /test: Read-only file system

root@sdrive:~# docker exec sdrive-stack-garage-1 touch /tmp/test
# Success — tmpfs is writable
```

## Service: Museum — The depends_on Dance

```yaml
depends_on:
  postgres:
    condition: service_healthy
  garage:
    condition: service_healthy
```

This is the ordered startup sequence. Docker will not start Museum until both Postgres AND Garage have passed their healthchecks. Without `condition: service_healthy`, Docker would only wait for the containers to *start* (the process is running), not for them to be *ready* (the service is accepting connections). The difference between "started" and "healthy" is the difference between "the JVM is loading classes" and "the API is serving requests."

I tested by stopping Garage and restarting the whole stack:

```bash
root@sdrive:~# docker compose down
root@sdrive:~# docker compose up -d
```

Watched the timing: Postgres healthy at +12s, Garage healthy at +16s, Museum started at +18s. Museum waited for both dependencies. If I had used the simpler `depends_on: [postgres, garage]` without the `condition`, Museum would have started immediately and crashed because Postgres wasn't ready yet.

## The Network: What Containers Actually See

I dove into the bridge network to understand exactly what each container sees:

```bash
root@sdrive:~# docker network inspect sdrive-stack_internal
[
    {
        "Name": "sdrive-stack_internal",
        "Driver": "bridge",
        "IPAM": {
            "Config": [{"Subnet": "172.18.0.0/16", "Gateway": "172.18.0.1"}]
        },
        "Containers": {
            "...postgres...": {"IPv4Address": "172.18.0.2/16"},
            "...garage...": {"IPv4Address": "172.18.0.3/16"},
            "...museum...": {"IPv4Address": "172.18.0.4/16"}
        }
    }
]
```

Three containers on a `/16` bridge subnet. Docker's embedded DNS (running at `127.0.0.11` inside each container's network namespace) resolves service names to these IPs. When Museum connects to `postgres:5432`, Docker DNS returns `172.18.0.2`, and the TCP connection traverses the bridge.

The bridge itself is a virtual Ethernet switch implemented by the Linux kernel. I could see it with the host's `ip` command:

```bash
root@sdrive:~# ip link show type bridge
br-a1b2c3d4e5f6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
```

Packets between containers never touch the physical `eth0` interface. They traverse the virtual bridge entirely in kernel memory. The only traffic that hits the wire is Museum's published port 8080, where Docker's `docker-proxy` accepts connections on the host and forwards them into the container's namespace via the bridge.

## Failure Modes: What Happens When Each Service Dies

I systematically killed each service and observed the cascade:

**PostgreSQL dies:** Museum loses its database connection. API calls that require auth fail immediately. The health endpoint still returns `{"status":"ok"}` because Museum's healthcheck is a self-check, not a dependency check. Photos that are already cached in Museum's memory can still be served from Garage. Docker restarts Postgres within 3 seconds; Museum's connection pool reconnects automatically within 10 seconds.

**Garage dies:** Museum can still serve metadata (album lists, user info) from Postgres. But photo uploads fail with S3 connection errors, and photo downloads fail for any images not in Museum's cache. Docker restarts Garage within 3 seconds; the cluster layout persists in the volume, so Garage resumes serving immediately without re-initialization.

**Museum dies:** The phone app loses its API endpoint. No uploads, no downloads, no authentication. But Postgres and Garage continue running independently — all data is safe. Docker restarts Museum within 5 seconds (longer `start_period`); the app automatically reconnects.

**All three die simultaneously (power failure):** Docker's restart policy brings them back in dependency order after reboot: Postgres first, Garage next, Museum last. The persistent journal from Day 17 records the crash. The SSD volumes preserve all data. This is the scenario that Week 01's power-pull test validated at the filesystem level — now we've validated it at the application level.

The exit criteria for Week 03 asks me to "hand-draw the service graph from memory and explain what each service does, where its data lives, how the others reach it, and what happens when each one dies." After today's deep-read and failure lab, I can do exactly that. The Compose file is not a magic incantation anymore. It's a system description I understand completely.

Tomorrow: Week 03 retrospective and the weekly article.
