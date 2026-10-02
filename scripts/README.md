# sdrive — Operational & Provisioning Scripts

This directory contains shell scripts used for host verification, OS provisioning, serial hardware debugging, network diagnostics, container monitoring, volume backup, self-healing watchdogs, benchmark telemetry, and Tailscale overlay networking throughout the 12-week build log.

Total: **20 scripts** as of Week 05 (Day 37).

---

## Script Index

### Host & Hardware (6 scripts)

| Script | Purpose | Added |
|---|---|---|
| `verify-env.sh` | Audits the local host development toolchain. | Week 00 |
| `flash-sd.sh` | Safely flashes Armbian OS images to microSD cards. | Week 00 |
| `serial-console.sh` | Opens a 1.5 Mbaud serial console to the RK3566 SoC. | Week 01 |
| `bootstrap-node.sh` | Idempotent system hardening and provisioning. | Week 01 |
| `diag-hardware.sh` | CPU thermals, frequencies, governors, ZRAM, block devices. | Week 01 |
| `power-pull-test.sh` | Filesystem durability test for ungraceful power-cut verification. | Week 02 |

### Network (3 scripts)

| Script | Purpose | Added |
|---|---|---|
| `diag-network.sh` | Network connectivity audit: interfaces, routing, DNS, ports, UFW. | Week 02 |
| `simulate-network-breakage.sh` | Deliberate network failure lab. | Week 02 |
| `sdrive-tailscale-health.sh` | Tailscale health: daemon, peers, NAT, DERP, interface. | Week 05 |

### Observability (5 scripts)

| Script | Purpose | Added |
|---|---|---|
| `sdrive-health-watchdog.sh` | Background daemon: SoC thermals, CPU, RAM, disk as JSON. | Week 01 |
| `sdrive-network-watchdog.sh` | Network liveness monitor with auto-restart. | Week 02 |
| `sdrive-golden-signals.sh` | Four Golden Signals health snapshot. | Week 02 |
| `monitor-resources.sh` | Real-time process, memory, and I/O telemetry dashboard. | Week 02 |
| `sdrive-storage-monitor.sh` | SSD capacity, SMART health, inodes, backup freshness. | Week 04 |

### Containers & Backup (4 scripts)

| Script | Purpose | Added |
|---|---|---|
| `sdrive-container-health.sh` | Docker container dashboard: status, health, restarts. | Week 03 |
| `sdrive-stack-backup.sh` | Metadata volume backup: tar.gz, manifest, 5-copy retention. | Week 03 |
| `sdrive-blob-backup.sh` | Incremental blob backup: rsync, bandwidth-limited, checksummed. | Week 04 |
| `garage-init-layout.sh` | One-time Garage cluster init: node role, bucket, API keys. | Week 03 |

### Security (1 script)

| Script | Purpose | Added |
|---|---|---|
| `setup-gitleaks-hook.sh` | Git pre-commit hook for secret scanning via gitleaks. | Week 00 |

### Extras (1 script)

| Script | Purpose | Added |
|---|---|---|
| `README.md` | This file — script index and usage reference. | Week 00 |
