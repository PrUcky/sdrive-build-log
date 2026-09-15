# Docker Container Troubleshooting Guide

*Reference: weeks/week-03/day-24.md*

Quick-reference diagnostic guide for the sdrive container stack. Every command was validated on the ROCK 3C during the Week 03 failure lab.

---

## Quick Health Check

```bash
# All-in-one status
docker compose ps

# Detailed per-container resources
docker stats --no-stream

# Custom dashboard
./scripts/sdrive-container-health.sh
```

---

## Common Failure Scenarios

### Museum returns `{"status":"error"}`

```bash
# Check museum logs for the error
docker logs sdrive-stack-museum-1 --tail 50

# Verify Postgres is reachable
docker exec sdrive-stack-museum-1 nslookup postgres

# Verify Garage is reachable
docker exec sdrive-stack-museum-1 curl -s http://garage:3903/health

# Check if museum can reach the database
docker exec sdrive-stack-postgres-1 pg_isready -U pguser -d ente_db
```

### Container in restart loop

```bash
# Check restart count
docker inspect sdrive-stack-museum-1 --format '{{.RestartCount}}'

# Check exit code of last failure
docker inspect sdrive-stack-museum-1 --format '{{.State.ExitCode}}'
# Exit 137 = OOM killed
# Exit 1   = application error
# Exit 0   = clean shutdown (shouldn't restart)

# Check for OOM events
docker inspect sdrive-stack-museum-1 --format '{{.State.OOMKilled}}'

# Check kernel OOM logs
journalctl -k --grep="oom\|Out of memory" --since "1 hour ago"
```

### Garage returns S3 errors

```bash
# Check if layout is initialized
docker exec sdrive-stack-garage-1 /garage status

# Check if bucket exists
docker exec sdrive-stack-garage-1 /garage bucket list

# Check if key has access
docker exec sdrive-stack-garage-1 /garage key list
docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen

# Re-initialize if needed (idempotent)
./scripts/garage-init-layout.sh
```

### Photo uploads failing

```bash
# Check storage quota
docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c \
  "SELECT user_id, storage_limit FROM subscriptions;"
# storage_limit should be -1 (unlimited)
# If not, see docs/first-account-setup.md Step 5

# Check Garage disk usage
docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen

# Check SSD free space
df -h /mnt/data
```

### Container DNS not resolving

```bash
# Verify Docker DNS is working
docker exec sdrive-stack-museum-1 nslookup postgres
# Should return 172.18.0.x

# Verify external DNS (configured in daemon.json)
docker exec sdrive-stack-museum-1 nslookup ente.io
# Should resolve via 1.1.1.1

# If DNS fails, check daemon.json
cat /etc/docker/daemon.json | grep dns
```

---

## Diagnostic Commands

### Logs

```bash
# Live log stream (all containers)
docker compose logs -f

# Last 100 lines for one container
docker logs sdrive-stack-museum-1 --tail 100

# Logs since a specific time
docker logs sdrive-stack-museum-1 --since 2026-09-15T10:00:00

# Filter for errors
docker logs sdrive-stack-museum-1 2>&1 | grep -i "error\|panic\|fatal"
```

### Network

```bash
# Inspect bridge network
docker network inspect sdrive-stack_internal

# Check which ports are published
docker port sdrive-stack-museum-1

# Verify no unexpected listeners on host
ss -tulnp
```

### Volumes

```bash
# List all volumes
docker volume ls

# Check volume disk usage
docker system df -v

# Inspect a specific volume
docker volume inspect sdrive-stack_postgres-data
```

### Security

```bash
# Verify read-only rootfs
docker inspect sdrive-stack-garage-1 --format '{{.HostConfig.ReadonlyRootfs}}'

# Verify no-new-privileges
docker inspect sdrive-stack-museum-1 --format '{{.HostConfig.SecurityOpt}}'

# Verify memory limits
docker inspect sdrive-stack-postgres-1 --format '{{.HostConfig.Memory}}'
```

---

## Nuclear Options

```bash
# Stop everything cleanly
docker compose down

# Stop and remove containers + networks (volumes preserved)
docker compose down --remove-orphans

# Full rebuild from images (volumes still preserved)
docker compose down && docker compose up -d --force-recreate

# ⚠️ DANGER: Remove ALL data (irreversible)
# docker compose down -v  # <-- deletes volumes!
```

---

## Performance Baselines (Week 03)

| Metric | Baseline | Warning Threshold |
|---|---|---|
| Total container memory | 188 MB | > 800 MB |
| Postgres RSS | 38 MB | > 256 MB |
| Garage RSS | 28 MB | > 128 MB |
| Museum RSS | 122 MB | > 384 MB |
| Container restart count | 0 | > 3 in 1 hour |
| Startup time (cold) | ~30s | > 120s |
| Health endpoint latency | < 50ms | > 500ms |
