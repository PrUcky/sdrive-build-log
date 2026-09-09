# Week 02 Retrospective — Networking, Properly

*September 4–9, 2026 · Days 14–19*

---

## Goal

> Understand what actually happens between a phone and a server, well enough to debug it rather than guess.

**Verdict: ACHIEVED.** The end-to-end packet walk on Day 18 proved the ability to narrate every step from URL to response and diagnose failures with the correct tool at each layer.

---

## Exit Criteria Assessment

| Criterion | Status | Evidence |
|---|---|---|
| Given an address, port, and URL, narrate every step from typing it to seeing a response | ✅ PASS | Day 18: 8-step annotated packet walk with verification tools at each layer |
| When it fails, reach for the right tool instead of guessing | ✅ PASS | Day 14: MTU crush diagnosed with `tcpdump`; Day 15: DNS poisoning detected with `dig`; Day 16: CGNAT confirmed with `traceroute`; Day 17: errors identified via `journalctl` |

---

## Milestone Inventory

### Day 14 — Subnets, TCP Handshakes, and Intentional Sabotage
- Mapped home subnet with `nmap -sn 192.168.1.0/24`
- Served HTTP on port 8000, captured full TCP 3-way handshake with `tcpdump`
- Executed MTU crush to 500 bytes via `simulate-network-breakage.sh`
- Verified `sdrive-network-watchdog.service` auto-recovered the interface in ~165 seconds

### Day 15 — DNS Lies, Firewall Walls, and the Routing Table
- Installed `dnsutils`, benchmarked DNS latency across 3 resolvers (Cloudflare: 8ms, Google: 12ms, Router: 14ms)
- Hardened `systemd-resolved` with multi-resolver failover, opportunistic DNS-over-TLS, DNSSEC allow-downgrade
- Pre-provisioned UFW rules for Week 03 services (museum 8080, Garage 3900, PostgreSQL 5432 localhost-only)
- Deliberately deleted the default route, observed clean `Network is unreachable` failure mode

### Day 16 — Dual-Stack, Socket Tables, and Tracing Every Hop
- Audited attack surface with `ss -tulnp`: 3 listening sockets (SSH dual-stack + resolved on loopback)
- Confirmed IPv6 is link-local only (`fe80::`), hardened `ufw6` to drop all inbound except NDP
- Traced 6-hop path to Cloudflare via `traceroute`, confirmed CGNAT at hop 2 (`100.64.0.1`)
- Demonstrated `curl -v` HTTP transaction lifecycle with annotated output format

### Day 17 — Logs as the Primary Signal and the Four Golden Signals
- Mastered `journalctl` filtering: by unit, time range, kernel messages, priority level
- Mapped the Four Golden Signals (Latency, Traffic, Errors, Saturation) to the sdrive appliance
- Created `scripts/sdrive-golden-signals.sh` — single-screen health snapshot in <2 seconds
- Enabled persistent journal storage surviving reboots, capped at 100MB / 30 days

### Day 18 — The Complete Network Map and the End-to-End Packet Walk
- Completed 8-step annotated packet walk proving exit criteria
- Rewrote `diagrams/network-topology.mermaid` with all empirically verified data
- Discovered Docker DNS stub resolver issue (`127.0.0.53` invisible to containers)
- Documented the complete network architecture with cross-references to all daily logs

### Day 19 — Retrospective and Weekly Article
- Formal exit criteria assessment (this document)
- Published weekly technical article: *Packets Don't Lie*

---

## Artifacts Produced

### Configuration Files
| File | Purpose |
|---|---|
| `config/systemd/resolved.conf.d/01-sdrive-dns.conf` | Multi-resolver DNS hardening with DoT and DNSSEC |

### Scripts
| File | Purpose |
|---|---|
| `scripts/sdrive-golden-signals.sh` | Four Golden Signals health snapshot |

### Documentation
| File | Purpose |
|---|---|
| `docs/network-diagnostics-reference.md` | Complete diagnostic command cheatsheet |
| `docs/ufw-firewall-policy.md` | Authoritative firewall policy document |
| `benchmarks/week-02-network-baseline.md` | DNS latency, traceroute paths, TCP timing, attack surface |
| `diagrams/network-topology.mermaid` | Updated network topology with measured RTTs |

### Content
| File | Purpose |
|---|---|
| `content/articles/week-02-packets-dont-lie.md` | Weekly technical essay |

---

## Key Performance Numbers

| Metric | Value | Measured On |
|---|---|---|
| DNS latency (Cloudflare 1.1.1.1) | **8 ms** | Day 15 |
| DNS latency (Google 8.8.8.8) | **12 ms** | Day 15 |
| TCP 3-way handshake (LAN) | **0.89 ms** | Day 14 |
| Traceroute hops to Cloudflare | **6 hops** | Day 16 |
| CGNAT gateway RTT | **4.15 ms** | Day 16 |
| Listening sockets (attack surface) | **3** (SSH + resolved) | Day 16 |
| Network interface errors | **0** (all categories) | Day 17 |
| System uptime at retro | **10 days** | Day 19 |
| Kernel errors (24h window) | **0** | Day 17 |
| Memory utilization | **~4%** (142 MB / 3.7 GB) | Day 17 |

---

## Known Issues and Carry-Forward

| Issue | Severity | Planned Resolution |
|---|---|---|
| Docker containers cannot see `systemd-resolved` stub at `127.0.0.53` | **HIGH** | Week 03: configure Docker daemon DNS or use `--dns` flag |
| IPv6 never tested with a global unicast prefix | MEDIUM | Monitor; UFW6 hardening is preemptive |
| SD card is single point of failure for all networking config | MEDIUM | Week 04: storage redundancy and backup strategy |
| No automated alerting when Golden Signals breach thresholds | LOW | Week 11: status dashboard and alerting |

---

## Lessons Learned

1. **Break it to learn it.** Every networking concept was internalized by deliberately causing the failure, not by reading about it. The MTU crush, the route deletion, the DNS poisoning — each one converted abstract knowledge into muscle memory.

2. **Documentation reveals ignorance.** Writing the architecture doc on Day 18 exposed three things I didn't know I didn't know: ARP cache timeouts, UFW log destinations, and the Docker DNS stub resolver issue. Documentation is a diagnostic tool for your own understanding.

3. **Four numbers are enough.** The Golden Signals framework reduced the entire observability problem to four questions: how fast, how much, how broken, how full. Every metric we collect feeds into one of these four.

4. **The routing table is the most powerful data structure on the machine.** Two lines control the entire data plane. Understanding those two lines — and knowing how Tailscale will add a third — is the foundation for everything that follows.

---

*Week 02 complete. Week 03: Containers and the stack.*
