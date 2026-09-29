# sdrive — Operational & Provisioning Scripts

This directory contains shell scripts used for host verification, OS provisioning, serial hardware debugging, network diagnostics, container monitoring, volume backup, self-healing watchdogs, benchmark telemetry, and Tailscale overlay networking throughout the 12-week build log.

Total: **20 scripts** as of Week 05 (Day 33).

---

## Script Index

### Host & Hardware

| Script | Purpose | Usage |
|---|---|---|
| `verify-env.sh` | Audits the local host development toolchain (`ssh`, `gitleaks`, `bmaptool`, `picocom`, `fio`). | `./scripts/verify-env.sh` |
| `flash-sd.sh` | Safely flashes Armbian OS images to target microSD cards with block device guardrails. | `sudo ./scripts/flash-sd.sh <image.img> /dev/sdX` |
| `serial-console.sh` | Auto-detects USB-to-UART bridges and opens a 1,500,000 baud serial console to the RK3566 SoC. | `./scripts/serial-console.sh` |
| `bootstrap-node.sh` | Idempotent system hardening and provisioning (packages, sysctl, UFW, journald caps, watchdog). | `sudo ./scripts/bootstrap-node.sh` |
| `diag-hardware.sh` | Hardware health inspector: CPU thermals, frequencies, governors, ZRAM pools, block device topology. | `sudo ./scripts/diag-hardware.sh` |
| `power-pull-test.sh` | Filesystem durability test: writes SHA-256-checksummed blocks for ungraceful power-cut verification. | `./scripts/power-pull-test.sh write` / `--verify` |

### Network

| Script | Purpose | Usage |
|---|---|---|
| `diag-network.sh` | Network connectivity audit: interfaces, routing, gateway reachability, DNS latency, listening ports, UFW state. | `sudo ./scripts/diag-network.sh` |
| `simulate-network-breakage.sh` | Deliberate network failure lab: firewall blocks, DNS blackholes, MTU drops, gateway corruption. | `sudo ./scripts/simulate-network-breakage.sh <mode>` |
| `sdrive-tailscale-health.sh` | Tailscale connection health: daemon status, peer connectivity, NAT diagnostics, DERP relay check. | `./scripts/sdrive-tailscale-health.sh` |

### Observability

| Script | Purpose | Usage |
|---|---|---|
| `sdrive-health-watchdog.sh` | Background daemon: SoC thermals, CPU frequency, RAM, disk capacity as JSON telemetry. | Managed by `sdrive-health-watchdog.service` |
| `sdrive-network-watchdog.sh` | Network liveness monitor: auto-restarts networking on persistent connectivity loss. | Managed by `sdrive-network-watchdog.service` |
| `sdrive-golden-signals.sh` | Four Golden Signals health snapshot: latency, traffic, errors, saturation. | `./scripts/sdrive-golden-signals.sh` |
| `monitor-resources.sh` | Real-time process, memory, and I/O telemetry dashboard for all sdrive core daemons. | `sudo ./scripts/monitor-resources.sh` |
| `sdrive-storage-monitor.sh` | Storage health: SSD capacity thresholds, SMART health, inode usage, backup freshness. | `./scripts/sdrive-storage-monitor.sh` |

### Containers

| Script | Purpose | Usage |
|---|---|---|
| `sdrive-container-health.sh` | Docker container dashboard: status, health, CPU/memory, restart counts, events. | `./scripts/sdrive-container-health.sh` |
| `sdrive-stack-backup.sh` | Docker volume backup: timestamped tar.gz archives, manifest, 5-backup retention. | `./scripts/sdrive-stack-backup.sh [backup-dir]` |
| `sdrive-blob-backup.sh` | Incremental blob backup: rsync with bandwidth limiting, checksum verification, dry-run mode. | `./scripts/sdrive-blob-backup.sh <destination>` |
| `garage-init-layout.sh` | One-time Garage cluster init: assigns node role, creates bucket, generates API keys. | `./scripts/garage-init-layout.sh` |

### Security

| Script | Purpose | Usage |
|---|---|---|
| `setup-gitleaks-hook.sh` | Installs a git pre-commit hook to block commits containing secrets via `gitleaks protect`. | `./scripts/setup-gitleaks-hook.sh` |
