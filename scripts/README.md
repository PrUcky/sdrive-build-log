# sdrive — Operational & Provisioning Scripts

This directory contains shell scripts used for host verification, OS provisioning, serial hardware debugging, network diagnostics, self-healing watchdogs, and benchmark telemetry throughout the 12-week build log.

---

## Script Index

| Script | Purpose | Usage |
|---|---|---|
| `verify-env.sh` | Audits the local host development toolchain (`ssh`, `gitleaks`, `bmaptool`, `picocom`, `fio`). | `./scripts/verify-env.sh` |
| `flash-sd.sh` | Safely flashes Armbian OS images to target microSD cards with block device guardrails. | `sudo ./scripts/flash-sd.sh <image.img> /dev/sdX` |
| `serial-console.sh` | Auto-detects connected USB-to-UART bridges and opens a 1,500,000 baud serial console to the RK3566 SoC. | `./scripts/serial-console.sh` |
| `bootstrap-node.sh` | Idempotent system hardening and provisioning script (packages, sysctl, UFW, journald caps, watchdog). | `sudo ./scripts/bootstrap-node.sh` |
| `sdrive-health-watchdog.sh` | Background daemon polling SoC thermals, CPU frequency, RAM usage, and disk capacity into JSON telemetry. | Managed by `sdrive-health-watchdog.service` |
| `sdrive-network-watchdog.sh` | Network liveness monitor that auto-restarts networking and Tailscale upon persistent connectivity loss. | Managed by `sdrive-network-watchdog.service` |
| `diag-hardware.sh` | Hardware health inspector: CPU thermals, frequencies, governors, ZRAM pools, block device topology. | `sudo ./scripts/diag-hardware.sh` |
| `diag-network.sh` | Network connectivity audit: interfaces, routing, gateway reachability, DNS latency, listening ports, UFW state. | `sudo ./scripts/diag-network.sh` |
| `monitor-resources.sh` | Real-time process, memory, and I/O telemetry dashboard for all sdrive core daemons. | `sudo ./scripts/monitor-resources.sh` |
| `power-pull-test.sh` | Filesystem durability test harness: writes SHA-256-checksummed blocks for ungraceful power-cut verification. | `./scripts/power-pull-test.sh write` / `--verify` |
| `simulate-network-breakage.sh` | Deliberate network failure lab: injects firewall blocks, DNS blackholes, MTU drops, and gateway corruption. | `sudo ./scripts/simulate-network-breakage.sh <mode>` |
