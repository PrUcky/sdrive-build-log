# Week 00 — Retrospective: Orientation & Foundations

**Dates:** 2026-08-19 to 2026-08-26  
**Total Time Invested:** ~34.5 hours across 7 days  
**Phase Status:** Complete (100% of Week 00 objectives achieved)

---

## 1. Executive Summary

Week 00 was designed as a zero-code, conceptual grounding phase. The primary objective was to build the entire mental model, architectural boundaries, security policies, and decision records for `sdrive` *before* powering on the physical hardware or flashing an operating system. 

Over the course of the week, the project transitioned from an abstract concept into a fully structured public repository with locked-in cryptographic decisions, an AGPL-3.0 copyleft legal framework, automated secret scanning, five formal Architecture Decision Records (ADRs), and physical hardware inspection.

---

## 2. Planned vs. Delivered Milestones

| Milestone | Target File(s) | Status | Notes |
|---|---|---|---|
| Repository Architecture & Scaffolding | `docs/`, `diagrams/`, `config/garage/`, `scripts/`, `benchmarks/`, `hardware/`, `app/`, `content/`, `assets/` | **Delivered** | Full 12-week directory layout initialized with `.gitkeep` files. |
| Licensing | `LICENSE` | **Delivered** | GNU Affero General Public License v3.0 committed. |
| Security Guardrails | `.gitleaks.toml`, `~/.ssh/id_ed25519` | **Delivered** | Gitleaks pre-commit scanning validated with canary tokens; Ed25519 keypair generated with 100 KDF rounds. |
| Architectural Decision Records | `docs/decisions/0001`–`0005` | **Delivered** | 5 formal ADRs committed (Ente, ROCK 3C, Tailscale, Garage, SD Boot). |
| Master Architecture & Living Glossary | `docs/architecture.md`, `docs/glossary.md` | **Delivered** | Four-layer architecture documented; domain terms and analogies defined. |
| Hardware Unboxing & Inspection | Hardware on desk | **Delivered** | Radxa ROCK 3C, SanDisk Max Endurance 64GB card, passive heatsink, and 5V/3A PSU verified. |
| Daily Logs (Days 01–07) | `weeks/week-00/day-01.md` through `day-07.md` | **Delivered** | Rich, narrative first-person logs tracking all internal technical debates and friction. |
| Long-Form Technical Article | `content/articles/week-00-why-the-server-never-decrypts.md` | **Delivered** | Comprehensive essay analyzing zero-knowledge personal cloud architecture. |

---

## 3. Key Architectural Breakthroughs

### The Zero-Knowledge Domino Effect
On Day 01, the system was conceptualized as a standard self-hosted photo backup server (akin to Nextcloud or Immich). By Day 02, diving into Ente's source code revealed that enforcing zero-knowledge end-to-end encryption (E2EE) completely flips the computational burden:
- **Client-Side Compute:** Key derivation (`Argon2id`), authenticated symmetric encryption (`XChaCha20-Poly1305`), EXIF parsing, thumbnail rendering, and ML facial recognition happen exclusively on the mobile handset.
- **Server Sizing:** Because the server is mathematically blind and never processes pixels, CPU and RAM requirements plummeted. An expensive 8-core AI board (RK3576/RK3588 with NPU) would sit at 0% utilization. The humble, power-efficient Rockchip RK3566 (quad Cortex-A55 @ 1.8GHz) on the Radxa ROCK 3C is not just sufficient—it is ideal.

### Out-of-Band Pre-signed URL Ingestion
On Day 06, whiteboard tracing uncovered a critical flaw in the initial data flow diagram. The Go API server (`museum`) must **not** act as an inline proxy for file uploads.
- **The Flow:** Handset pings `museum` for upload authorization $\rightarrow$ `museum` generates an HMAC-SHA256 authenticated pre-signed PUT URL $\rightarrow$ Handset streams ciphertext blob directly into the `Garage` object storage daemon over Tailscale $\rightarrow$ Handset confirms upload to `museum` $\rightarrow$ `museum` updates PostgreSQL metadata.
- **The Impact:** Memory heap allocation in Go remains flat during multi-gigabyte backup batches. The data plane is cleanly decoupled from the metadata control plane.

### Choosing Garage over MinIO
MinIO’s evolution toward enterprise multi-node Kubernetes clusters introduces high baseline RAM consumption, aggressive disk formatting checks, and heavy telemetry. **Garage** (written in Rust by Deuxfleurs) runs as a single static binary, idles at under 50MB of RAM, and is purpose-built for low-power edge nodes with consumer flash storage.

---

## 4. Friction Log & Unforeseen Challenges

1. **Windows Git Credential Manager Hang:**
   - *Symptom:* CLI `git push` commands hung indefinitely in PowerShell without returning an error.
   - *Root Cause:* The Windows Credential Manager failed to display background OAuth prompts in non-interactive terminal subshells.
   - *Resolution:* Bypassed via GitHub MCP API toolchain for Week 00; local SSH agent and Git credentials will be formalized on the Linux host in Week 01.
2. **Power Delivery (USB-PD) Nuances:**
   - *Symptom:* Potential brownouts and phantom reboot risks if using standard multi-voltage laptop chargers.
   - *Root Cause:* Many SBCs lack dedicated USB-PD controller chips to negotiate high-voltage profiles, falling back to 5V but failing under transient current spikes.
   - *Resolution:* Standardized on a dedicated, regulated 5V/3A linear-switching power brick with heavy-gauge cabling.
3. **Cognitive Load & Pacing:**
   - *Symptom:* Mental fatigue after writing complex architectural decision records on Day 05.
   - *Resolution:* Took a deliberate 24-hour break on Day 06 (August 24th) before returning for the whiteboard proof and hardware unboxing. Building buffer days into the roadmap is non-negotiable for long-term project viability.

---

## 5. System Footprint & Budget Baseline

- **Hardware Cost (BOM):**
  - Radxa ROCK 3C (4GB LPDDR4): ~₹4,500 ($54)
  - SanDisk Max Endurance 64GB MicroSD: ~₹1,100 ($13)
  - Anodized Aluminum Passive Heatsink: ~₹250 ($3)
  - Regulated 5V/3A USB-C Power Supply: ~₹600 ($7)
  - **Total BOM:** ~₹6,450 (~$77 USD)
- **Power Target:** $\le 2.5\text{W}$ idle, $\le 6.0\text{W}$ peak load.
- **Estimated Idle RAM Breakdown:**
  - Linux Kernel + Systemd: ~120MB
  - PostgreSQL 16: ~60MB
  - Ente `museum` Daemon: ~40MB
  - Garage S3 Daemon: ~50MB
  - Tailscale Mesh Daemon: ~30MB
  - **Total Projected Baseline RAM:** $\approx 300\text{MB}$ (leaving $>3.5\text{GB}$ for Linux page cache).

---

## 6. Exit Criterion Verification

> **Week 00 Exit Criterion:** *"You wrote `0004-garage-over-minio.md` unaided. If you couldn't, spend another day here."*

**Audit Result:** **PASSED.**  
The technical rationale comparing memory allocation models, asynchronous I/O architectures, S3 API surface compatibility, and flash storage latency handling between MinIO and Garage is fully understood, defended in ADR 0004, and validated against the system's pre-signed URL ingestion pipeline.

---

## 7. Week 01 Handoff Plan (Linux & Board Bring-up)

- **Day 08:** Flash Armbian Bookworm (Mainline Linux 6.6 LTS) to microSD; connect USB-to-UART serial adapter; verify U-Boot SPL stage and capture first boot console logs.
- **Day 09:** First-boot configuration: create unprivileged user, configure hostname (`sdrive-node1`), set static IPv4/IPv6 addressing.
- **Day 10:** Security hardening: deploy Ed25519 public key to `~/.ssh/authorized_keys`, disable SSH password authentication, configure `ufw` firewall.
- **Day 11:** Network bring-up: install and authenticate Tailscale daemon, verify direct WireGuard peer-to-peer connectivity over cellular network.
- **Day 12:** Baseline telemetry: benchmark idle power draw, CPU thermal baseline under load (`stress-ng`), and microSD sequential/random I/O throughput via `fio`.
- **Day 13 (Week 01 Day 07):** Week 01 Retrospective and second long-form article.
