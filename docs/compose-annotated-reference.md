# Docker Compose Annotated Reference

*Reference: weeks/week-03/day-24.md*

Line-by-line explanation of every directive in the sdrive `docker-compose.yml`, verified through deliberate breakage testing on the ROCK 3C.

---

## Global Directives

| Directive | Value | Explanation |
|---|---|---|
| `version` | `"3.8"` | Compose file schema version. Ignored by Compose V2 (Go rewrite) but kept for backward compatibility. Removing it changes nothing. |

---

## Service: `postgres`

| Directive | Value | What Happens If Removed |
|---|---|---|
| `image` | `postgres:16-bookworm@sha256:...` | Without digest: Docker pulls whatever `:16-bookworm` currently points to, which may differ from what was tested. |
| `restart` | `unless-stopped` | Without: container stays dead after crash. No auto-recovery. |
| `POSTGRES_DB` | `ente_db` | Without: default database is `postgres`. Museum's `db.name` wouldn't match; connection fails. |
| `POSTGRES_USER` | `pguser` | Without: default user is `postgres`. Museum's `db.user` wouldn't match. |
| `POSTGRES_PASSWORD` | (secret) | Without: Postgres refuses to start (env var required by entrypoint). |
| `volumes` | `postgres-data:/var/lib/postgresql/data` | Without: data stored in container layer. Destroyed on `docker compose down`. |
| `deploy.resources.limits.memory` | `512M` | Without: Postgres can consume all 4 GB and OOM-kill other containers. |
| `security_opt` | `no-new-privileges:true` | Without: processes could escalate via setuid binaries. |
| `tmpfs` | `/tmp:32M, /run:16M` | Without: temp writes go to container layer (slower, uses overlay storage). |
| `healthcheck.test` | `pg_isready -U pguser -d ente_db` | Without: Museum's `depends_on: service_healthy` becomes `depends_on: service_started` — startup race condition. |
| `networks` | `internal` | Without: container joins the default bridge (less isolation, no embedded DNS for service names). |

---

## Service: `garage`

| Directive | Value | What Happens If Removed |
|---|---|---|
| `image` | `dxflrs/garage:v1.0.1` | Pinned to tag. No digest available for ARM64. Floating `:latest` would risk breaking changes. |
| `garage.toml` mount | `./garage.toml:/etc/garage.toml:ro` | Without: Garage uses default config. RPC secret is empty; S3 region is wrong; data dirs are inside container. |
| `garage-meta` volume | `/mnt/data/garage/meta` | Without: SQLite metadata (bucket index, key index) is lost on container recreation. |
| `garage-data` volume | `/mnt/data/garage/data` | Without: ALL encrypted photo blobs are lost on container recreation. |
| `read_only` | `true` | Without: attackers with code execution can persist backdoors in the container filesystem. |
| `healthcheck.test` | `curl -f http://localhost:3903/health` | Without: Museum may start before Garage is ready; S3 operations fail. |
| `healthcheck.start_period` | `15s` | Without: Garage marked unhealthy during slow startup; Docker may restart it prematurely. |

---

## Service: `museum`

| Directive | Value | What Happens If Removed |
|---|---|---|
| `depends_on.postgres.condition` | `service_healthy` | Without condition: Museum starts immediately, crashes because DB isn't ready, enters restart loop. |
| `depends_on.garage.condition` | `service_healthy` | Without: Museum starts before Garage; S3 calls fail; upload errors on first request. |
| `ports` | `"8080:8080"` | Without: Museum runs but is unreachable from outside Docker's bridge network. No phone access. |
| `museum.yaml` mount | `./museum.yaml:/museum.yaml:ro` | Without: Museum uses defaults. DB host would be `localhost` (wrong in container context). S3 creds missing. |
| `ENTE_CREDENTIALS_FILE` | `/museum.yaml` | Without: Museum looks for config at default path, not our custom mount. Startup fails. |
| `read_only` | `true` | Without: writable rootfs allows persistent compromise. |
| `healthcheck.start_period` | `30s` | Without: Museum marked unhealthy during DB migration (first boot). Docker restarts it before migrations finish; infinite loop. |

---

## Volumes Section

```yaml
volumes:
  postgres-data:
    driver: local
  garage-meta:
    driver: local
  garage-data:
    driver: local
  museum-data:
    driver: local
```

Named volumes declared here persist on the SSD at `/mnt/data/docker/volumes/<project>_<name>/_data/`. The `local` driver uses the host filesystem. Volumes survive `docker compose down` but are destroyed by `docker compose down -v` (the nuclear option).

---

## Networks Section

```yaml
networks:
  internal:
    driver: bridge
```

Creates an isolated bridge network (`172.18.0.0/16`). Containers get IPs assigned sequentially: postgres at `.2`, garage at `.3`, museum at `.4`. Docker's embedded DNS at `127.0.0.11` resolves service names to these IPs.

Traffic between containers stays on the bridge — it never hits the physical `eth0`. Only Museum's published port creates a `docker-proxy` listener on the host.
