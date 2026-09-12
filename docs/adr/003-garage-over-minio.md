# ADR-003: Replace MinIO with Garage as S3 Object Store

**Status:** Accepted  
**Date:** 2026-09-12  
**Deciders:** Pratyush Chaudhary  

---

## Context

The sdrive appliance requires an S3-compatible object storage engine to hold encrypted photo blobs. Ente's `museum` backend communicates with the object store exclusively via the S3 API (PutObject, GetObject, DeleteObject, ListBuckets), making any S3-compatible implementation a valid backend.

The stock Ente quickstart uses **MinIO** — a popular, feature-rich, Go-based S3 server. The question is whether MinIO is the right choice for a resource-constrained single-board computer (Radxa ROCK 3C, 4 GB RAM, quad Cortex-A55).

## Decision

Replace MinIO with **Garage** (https://garagehq.deuxfleurs.fr/) — a lightweight, Rust-based, S3-compatible distributed storage engine designed for self-hosted and edge deployments.

## Rationale

### Memory Footprint

| Engine | Idle RSS | Under Load |
|---|---|---|
| MinIO | ~92 MB | ~150–200 MB |
| Garage | ~28 MB | ~45–60 MB |

On a 4 GB board running PostgreSQL (~38 MB), Museum (~124 MB), and the host OS (~158 MB overhead), every megabyte counts. Garage saves **~60 MB at idle** — that's 1.6% of total RAM freed for page cache, which directly improves I/O performance for photo reads.

### Binary Complexity

- **MinIO:** Go binary with embedded web console, IAM engine, versioning, replication, encryption-at-rest, tiering, and observability stack. Most features are irrelevant for sdrive (encryption happens client-side, single-node means no replication).
- **Garage:** Single Rust binary with minimal feature surface: S3 API, bucket management, key management, and optional web hosting. No embedded console, no IAM beyond API keys, no unnecessary subsystems.

Complexity is attack surface. Fewer features = fewer CVEs.

### Single-Node Suitability

MinIO is designed for distributed clusters. Its single-node mode works but is explicitly documented as "for evaluation only." Garage treats single-node deployment as a first-class configuration with `replication_factor = 1`.

### S3 API Compatibility

Museum uses a narrow S3 API surface: `PutObject`, `GetObject`, `DeleteObject`, `HeadObject`, `CreateBucket`, `ListBuckets`. Both MinIO and Garage support this subset fully. Museum cannot tell the difference between MinIO and Garage — the swap was transparent.

### Database Engine

Garage uses SQLite for its metadata store (configurable to LMDB or Sled). SQLite is the most battle-tested embedded database in existence, with a test suite that exceeds 100% branch coverage. This is the right choice for an edge appliance where metadata volume is low and reliability is paramount.

## Consequences

### Positive
- 60 MB RAM savings at idle, more under load
- Smaller attack surface (fewer features = fewer vulnerabilities)
- Single static binary, trivial to update
- Purpose-built for edge/self-hosted deployments

### Negative
- Less community adoption than MinIO (fewer Stack Overflow answers)
- No web console (all management via CLI: `garage status`, `garage bucket`, `garage key`)
- Cluster layout initialization is a manual step (automated by `scripts/garage-init-layout.sh`)

### Neutral
- Image digest pinning works identically
- Healthcheck endpoint available at `:3903/health`
- Volume mount pattern unchanged (data persists on USB SSD)

## Alternatives Considered

1. **Keep MinIO:** Higher memory cost, unnecessary feature complexity, but zero migration effort.
2. **SeaweedFS:** Interesting Go-based alternative, but higher memory usage than Garage and more complex topology.
3. **Raw filesystem storage:** Museum doesn't support direct filesystem backends — it requires S3 API.

---

*Supersedes: MinIO from the stock Ente quickstart (Day 21 baseline).*
