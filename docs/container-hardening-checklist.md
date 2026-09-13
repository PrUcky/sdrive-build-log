# Container Hardening Checklist

*Reference: weeks/week-03/day-23.md*

This checklist documents every hardening measure applied to the sdrive container stack, why each matters, and how to verify it.

---

## 1. Memory Limits

| Container | Limit | Reservation | Rationale |
|---|---|---|---|
| postgres | 512 MB | 64 MB | Prevents PG shared buffers from consuming all RAM during heavy queries |
| garage | 256 MB | 32 MB | Garage is extremely lean; 256 MB is 9x its idle footprint |
| museum | 512 MB | 128 MB | Go's GC can be aggressive with heap growth; cap prevents OOM cascading |

**Why this matters:** Without memory limits, a single container can exhaust all 4 GB of RAM and trigger the kernel's OOM killer, which may kill a *different* container to free memory. Memory limits contain the blast radius.

**Verify:**
```bash
docker inspect sdrive-stack-postgres-1 | grep -A 3 "Memory"
```

---

## 2. no-new-privileges

```yaml
security_opt:
  - no-new-privileges:true
```

Prevents processes inside the container from gaining additional privileges via `setuid` binaries, `sudo`, or capability escalation. Even if an attacker achieves code execution inside a container, they cannot escalate beyond the container's initial privilege set.

**Verify:**
```bash
docker inspect sdrive-stack-museum-1 --format '{{.HostConfig.SecurityOpt}}'
# Expected: [no-new-privileges:true]
```

---

## 3. Read-Only Root Filesystem

```yaml
read_only: true
tmpfs:
  - /tmp:size=64M
```

Applied to `garage` and `museum`. The container's root filesystem is mounted read-only, preventing any process from writing to the image layers. Transient writes (temp files, sockets) go to a `tmpfs` mount that lives in RAM and is size-capped.

PostgreSQL cannot use a read-only rootfs because it writes to `/var/run/postgresql/` for the Unix socket.

**Verify:**
```bash
docker inspect sdrive-stack-garage-1 --format '{{.HostConfig.ReadonlyRootfs}}'
# Expected: true
```

---

## 4. Pinned Image Digests

```yaml
image: postgres:16-bookworm@sha256:3d9ed83...
```

Every image is pinned to a SHA-256 digest, not a floating tag. This guarantees that `docker compose up` in month 4 produces exactly today's system. Floating `:latest` tags silently pull new versions that may have breaking changes, different defaults, or supply-chain compromises.

**Exception:** `ghcr.io/ente-io/server:latest` is currently unpinned because the Ente team's ARM64 builds don't publish stable digest tags. This will be pinned once a stable release tag is available.

**Verify:**
```bash
docker images --digests | grep postgres
```

---

## 5. Log Rotation

Configured globally in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Each container's stdout/stderr is capped at 10 MB across 3 rotated files. Maximum 30 MB per container, 90 MB for the entire stack. Unbounded container logs are the #1 cause of disk exhaustion in long-running embedded deployments.

**Verify:**
```bash
ls -la /mnt/data/docker/containers/*/
# Log files should never exceed 10 MB
```

---

## 6. Healthchecks with Startup Grace Period

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 15s
  timeout: 5s
  retries: 5
  start_period: 30s
```

The `start_period` gives containers time to initialize before the first health check. Without it, slow-starting services like Museum (which runs database migrations on first boot) would be marked unhealthy and restarted in a loop.

**Verify:**
```bash
docker inspect sdrive-stack-museum-1 --format '{{.State.Health.Status}}'
# Expected: healthy
```

---

## 7. Restart Policy

```yaml
restart: unless-stopped
```

Containers automatically restart after crashes but stay stopped after a manual `docker compose stop`. This prevents:
- Infinite restart loops from consuming CPU (combined with healthcheck backoff)
- Surprise restarts after intentional maintenance shutdowns

---

## 8. Internal Network Isolation

```yaml
networks:
  - internal
```

All containers communicate over a dedicated bridge network. Only Museum publishes a port to the host (`8080:8080`). PostgreSQL and Garage have zero host-facing ports — they are unreachable from outside Docker's bridge.

**Verify:**
```bash
ss -tulnp | grep -v docker-proxy | grep -v sshd
# Only systemd-resolved on loopback should remain
```

---

## Summary Table

| Measure | postgres | garage | museum |
|---|---|---|---|
| Memory limit | 512M | 256M | 512M |
| no-new-privileges | ✅ | ✅ | ✅ |
| Read-only rootfs | ❌ (needs /var/run) | ✅ | ✅ |
| Pinned digest | ✅ | ✅ (tag) | ❌ (pending) |
| Log rotation | ✅ (global) | ✅ (global) | ✅ (global) |
| Healthcheck | pg_isready | /health:3903 | /health:8080 |
| start_period | — | 15s | 30s |
| Restart policy | unless-stopped | unless-stopped | unless-stopped |
| Network isolation | internal only | internal only | internal + :8080 |
