# sdrive — Operational & Provisioning Scripts

This directory contains shell scripts used for host verification, OS provisioning, serial hardware debugging, and benchmark telemetry throughout the 12-week build log.

---

## Script Index

| Script | Purpose | Usage |
|---|---|---|
| `verify-env.sh` | Audits the local host development toolchain (`ssh`, `gitleaks`, `bmaptool`, `picocom`, `fio`). | `./scripts/verify-env.sh` |
| `flash-sd.sh` | Safely flashes Armbian OS images to target microSD cards with block device guardrails. | `sudo ./scripts/flash-sd.sh <image.img> /dev/sdX` |
| `serial-console.sh` | Auto-detects connected USB-to-UART bridges and opens a 1,500,000 baud serial console to the RK3566 SoC. | `./scripts/serial-console.sh` |
