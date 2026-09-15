# Week 03 Retrospective — Containers and the Stack

*September 10–15, 2026 · Days 20–25*

---

## Goal

> The sdrive stack running on the board, on Garage, with a baseline you can trust.

**Verdict: ACHIEVED.** PostgreSQL, Garage, and Museum are running as hardened Docker containers on the ROCK 3C, with the first user account registered, trial quota removed, and all data persisting on the USB SSD.

---

## Exit Criteria Assessment

| Criterion | Status | Evidence |
|---|---|---|
| Hand-draw the service graph from memory | ✅ PASS | Day 25: narrated the complete graph with data paths, ports, and failure modes |
| Explain what each service does | ✅ PASS | Day 24: Compose deep-read with line-by-line analysis |
| Where each service's data lives | ✅ PASS | Day 20-23: SSD volumes, fstab persistence, backup script |
| How the services reach each other | ✅ PASS | Day 24: Docker bridge DNS, 172.18.0.0/16 subnet, network inspection |
| What happens when each one dies | ✅ PASS | Day 24: systematic kill tests for all three services |

---

## Milestone Inventory

### Day 20 — The SSD Mount and Container Primer
- Partitioned 500 GB USB SSD, mounted at `/mnt/data` with `noatime,discard`
- Persisted via UUID in `/etc/fstab`, verified reboot survival
- Installed Docker Engine, moved `data-root` to SSD
- Configured `daemon.json`: DNS bypass, log rotation (10 MB × 3), overlay2 driver
- Demonstrated container lifecycle: images vs containers vs volumes

### Day 21 — Stock Ente Quickstart (Baseline)
- Wrote `docker-compose.yml` with PostgreSQL + MinIO + Museum
- Pinned Postgres image digest for reproducibility
- Healthcheck-gated startup ordering (`depends_on: service_healthy`)
- First `docker compose up`: all three services healthy
- Verified `{"status":"ok"}` from desktop: `curl http://192.168.1.150:8080/health`

### Day 22 — MinIO → Garage Swap
- Replaced MinIO with Garage (Rust S3 daemon)
- Memory savings: 92 MB → 28 MB (69% reduction)
- Created `garage-init-layout.sh` for idempotent cluster initialization
- Documented decision in ADR-003
- Drew complete service graph with Mermaid diagram

### Day 23 — First Account and Container Hardening
- Registered first user account via Ente app
- Read verification OTP from container logs (no SMTP needed)
- Promoted account to admin, removed trial storage quota
- Hardened all containers: memory limits, `no-new-privileges`, read-only rootfs, tmpfs
- Created volume backup script with 5-backup retention

### Day 24 — Compose Deep-Read and Failure Lab
- Line-by-line analysis of every Compose directive
- Tested image digest verification, restart policies, volume persistence
- Explored Docker bridge network internals (172.18.0.0/16, embedded DNS)
- Systematic failure lab: killed each service, observed cascade and recovery

### Day 25 — Retrospective and Weekly Article
- Formal exit criteria assessment (this document)
- Published weekly article: *Three Containers on a 4 GB Board*

---

## Artifacts Produced

### Configuration Files
| File | Purpose |
|---|---|
| `config/docker/daemon.json` | Docker daemon config: SSD data-root, DNS, log rotation |
| `config/garage/garage.toml` | Garage S3 storage engine configuration |
| `compose/docker-compose.yml` | Hardened 3-service Compose stack |
| `compose/museum.yaml` | Museum backend config with admin template |

### Scripts
| File | Purpose |
|---|---|
| `scripts/sdrive-container-health.sh` | Container health dashboard |
| `scripts/sdrive-stack-backup.sh` | Volume backup with retention |
| `scripts/garage-init-layout.sh` | One-time Garage cluster initialization |

### Documentation
| File | Purpose |
|---|---|
| `docs/first-account-setup.md` | Account registration and admin guide |
| `docs/container-hardening-checklist.md` | 8-point hardening checklist |
| `docs/docker-troubleshooting.md` | Diagnostic commands and failure scenarios |
| `docs/adr/003-garage-over-minio.md` | Architecture decision: Garage vs MinIO |
| `diagrams/service-graph.mermaid` | Container service graph with data flow |

### Content
| File | Purpose |
|---|---|
| `content/articles/week-03-three-containers.md` | Weekly technical essay |

---

## Key Performance Numbers

| Metric | Value | Context |
|---|---|---|
| Total container memory (Garage) | **188 MB** | vs 254 MB with MinIO |
| Postgres RSS | **38 MB** | Idle, single user |
| Garage RSS | **28 MB** | vs MinIO 92 MB (69% savings) |
| Museum RSS | **122 MB** | Go heap + GC overhead |
| Total system memory | **348 MB** / 3,788 MB (**9%**) | Includes host + Docker daemon |
| SSD used | **15 GB** / 458 GB (**3%**) | OS + Docker images + empty volumes |
| CPU temperature (3 containers) | **49–52°C** | vs 47°C bare system |
| Cold start to all healthy | **~30 seconds** | Postgres → Garage → Museum |
| Container restart (kill -9) | **~3 seconds** | Docker restart policy |
| Volume backup size (metadata) | **2.3 MB** | Excludes photo blobs |
| Docker images total | **~680 MB** | Postgres + Garage + Museum |

---

## Known Issues and Carry-Forward

| Issue | Severity | Planned Resolution |
|---|---|---|
| Museum image uses floating `:latest` tag | **HIGH** | Pin to digest once stable ARM64 release available |
| Postgres cannot use read-only rootfs | LOW | Known upstream limitation, mitigated by `no-new-privileges` |
| No automated backup schedule (cron) | MEDIUM | Week 04: add cron job for `sdrive-stack-backup.sh` |
| No blob-level backup strategy | MEDIUM | Week 04: storage architecture design |
| No TLS on Museum endpoint (plain HTTP) | MEDIUM | Week 06: Caddy reverse proxy with auto-HTTPS |

---

## Lessons Learned

1. **Build order is the point.** SSD first, baseline second, swap third. Each step produced a known-good state. When something breaks, you know exactly which change caused it because you only changed one thing.

2. **The trial trap is real.** A fresh Ente self-hosted account has a storage quota that silently kills imports. Removing it (`update-subscription --no-limit`) must happen before any serious photo upload or you'll spend a day debugging a phantom bug.

3. **Garage is the right choice for edge deployments.** 28 MB vs 92 MB is the difference between comfortable headroom and constant memory pressure on a 4 GB board. The smaller attack surface is a bonus.

4. **Containers share a kernel.** Memory limits aren't optional on embedded boards. Without them, one container's leak can OOM-kill an innocent neighbor. The `deploy.resources.limits` directive is the blast radius containment for shared-kernel isolation.

5. **Volumes are the only thing that matters.** Containers are disposable. Images are downloadable. Configuration is in version control. But volumes contain irreplaceable state — encryption key bundles, user accounts, subscription records. The backup script runs in 3 seconds and produces a 2.3 MB archive that is worth more than the entire rest of the system.

---

*Week 03 complete. Week 04: Storage architecture and photo import preparation.*
