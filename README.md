# sdrive - Build Log

A daily build log tracking progress on the **sdrive** home photo-backup appliance across 12 weeks (78 days).

This repository is the living document of the entire build process, from bare hardware unboxing to a fully branded, end-to-end encrypted local cloud replacement.

## Project Structure

- `docs/` — Architecture, decision records, threat model, kernel tuning guides, and glossary.
  - `docs/decisions/` — Architectural Decision Records (ADRs).
- `weeks/` — Daily first-person engineering logs, grouped by week.
- `diagrams/` — Mermaid architecture, ingestion sequence, and network topology diagrams.
- `config/` — Configuration files and service units for the stack.
  - `config/garage/` — Garage S3 object storage backend.
  - `config/ssh/` — OpenSSH daemon hardening drop-in.
  - `config/sysctl/` — Linux kernel virtual memory and network buffer tuning.
  - `config/systemd/` — Custom systemd service units and journald caps.
  - `config/tailscale/` — Tailscale WireGuard mesh provisioning and ACL policy.
- `scripts/` — Provisioning, diagnostics, benchmarking, and self-healing scripts.
- `benchmarks/` — Power-draw, temperature, network throughput, and resilience telemetry.
- `hardware/` — Bill of Materials (BOM) and board hardware specifications.
- `content/` — Long-form weekly technical articles and essays.
- `app/` — *(Planned)* The customized mobile client source code.
- `assets/` — *(Planned)* Images and screenshots used in logs.

## The Schedule

| Week | Focus | Days |
|---|---|---|
| week-00 | Orientation | 01–07 |
| week-01 | Linux & Board Bring-up | 08–13 |
| week-02 | Networking | 14–19 |
| week-03 | Containers | 20–25 |
| week-04 | Storage & Durability | 26–31 |
| week-05 | First Real Loop | 32–37 |
| week-06 | Mesh & HTTPS | 38–43 |
| week-07 | Learning to Program / Mobile App | 44–49 |
| week-08 | Rebrand | 50–55 |
| week-09 | Subtraction | 56–61 |
| week-10 | Consolidate | 62–67 |
| week-11 | Web & Status | 68–73 |
| week-12 | Measure & Harden | 74–78 |

## License

This project is licensed under the **AGPL-3.0 License**. See the [LICENSE](LICENSE) file for more details.
