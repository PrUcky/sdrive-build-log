# Week 05 Retrospective — Tailscale and the Overlay Network

*September 29 – October 2, 2026 · Days 32–37*

---

## Goal

> Make the appliance reachable from outside the local network through an embedded overlay network, bypassing CGNAT. Prove Gate A by October 4.

**Verdict: ACHIEVED.** Tailscale installed, tunnel proven across three network paths, Gate A evidence assembled with 11/11 criteria passed.

---

## Exit Criteria Assessment

| Criterion | Status | Evidence |
|---|---|---|
| Tailscale installed and authenticated | ✅ PASS | Day 32: v1.72.1, systemd, 24 MB |
| Tunnel works through ISP CGNAT | ✅ PASS | Day 32: hole-punched, 44 ms |
| Photo upload through tunnel | ✅ PASS | Day 33: WiFi + mobile data |
| Photo download through tunnel | ✅ PASS | Day 33: 1.2s full-res on mobile |
| Multi-device photo viewing | ✅ PASS | Day 33: phone A → server → phone B |
| Account isolation over tunnel | ✅ PASS | Day 33: zero cross-leak |
| Throughput benchmarked (3 paths) | ✅ PASS | Day 34: LAN/mobile/DERP |
| DERP relay fallback works | ✅ PASS | Day 34: 112 ms, 1.1 MB/s |
| Automatic path recovery | ✅ PASS | Day 34: WiFi→mobile→WiFi seamless |
| Gate A evidence assembled | ✅ PASS | Day 35: docs/gate-a-evidence.md |
| MagicDNS hostname active | ✅ PASS | Day 36: sdrive.tail*.ts.net |
| HTTPS certificate provisioned | ✅ PASS | Day 36: Let's Encrypt via Tailscale |

---

## Milestone Inventory

### Day 32 — Tailscale Installation and First Tunnel
- Installed Tailscale v1.72.1, authenticated to tailnet
- Three devices: sdrive (100.100.42.17), desktop, phone
- Direct tunnel through CGNAT: 44 ms from mobile data
- Museum reachable via tunnel: `curl http://100.100.42.17:8080/health`
- UFW updated: `allow in on tailscale0`
- Attack surface: +1 UDP listener (cryptographically invisible)

### Day 33 — First Photo Through the Tunnel
- Ente app configured with Tailscale IP endpoint
- Upload from WiFi (0.5s) and mobile data (1.8s)
- Download: thumbnails 300 ms, full-res 1.2s on mobile
- Multi-device: phone A uploads, phone B views through tunnel
- Account isolation verified: separate accounts, zero cross-leak
- Batch: 20 photos (72 MB) in 35s over 4G

### Day 34 — Tunnel Throughput Benchmarks
- LAN Direct: 382 Mbps tunnel, 6.3 MB/s photo upload, 3 ms
- Mobile Direct: 17.3 Mbps tunnel, 2.0 MB/s photo upload, 46 ms
- DERP Relay: 7.8 Mbps tunnel, 1.1 MB/s photo upload, 112 ms
- WireGuard tunnel is NEVER the bottleneck
- Automatic path recovery: 5–15 second switchover, zero lost uploads

### Day 35 — Gate A Evidence Package
- Final verification run: all systems green
- Demo scenario proven end-to-end from mobile data
- Evidence document: 11/11 criteria with daily log references
- Gate A: READY

### Day 36 — MagicDNS and HTTPS Roadmap
- MagicDNS enabled: `sdrive.tail12345.ts.net`
- Let's Encrypt certificate provisioned via Tailscale DNS-01
- Caddy reverse proxy architecture drafted
- URL evolution: LAN IP → Tailscale IP → MagicDNS HTTPS
- Week 06 Compose stack sketched (4 containers)

### Day 37 — Retrospective and Weekly Article
- Formal exit criteria assessment (this document)
- Published weekly article: *Punching Through CGNAT*

---

## Artifacts Produced

### Scripts
| File | Purpose |
|---|---|
| `scripts/sdrive-tailscale-health.sh` | Tailscale health: daemon, peers, NAT, DERP, interface |

### Documentation
| File | Purpose |
|---|---|
| `docs/gate-a-evidence.md` | Gate A evidence package (11/11 criteria) |
| `docs/tailscale-configuration.md` | Complete Tailscale config reference |
| `docs/adr/004-tailscale-over-wireguard.md` | ADR: Tailscale vs raw WireGuard decision |

### Diagrams
| File | Purpose |
|---|---|
| `diagrams/network-topology.mermaid` | Updated with Tailscale overlay and DERP paths |

### Configuration
| File | Purpose |
|---|---|
| `config/cron/sdrive-crontab` | v2: added Tailscale health + blob backup |

### Content
| File | Purpose |
|---|---|
| `content/articles/week-05-punching-through-cgnat.md` | Weekly technical essay |

---

## Key Performance Numbers

| Metric | Value | Context |
|---|---|---|
| Tailscale daemon memory | 24–26 MB | Go binary, stable |
| WireGuard tunnel (LAN) | 382 Mbps | 91% of raw WiFi 5 |
| WireGuard tunnel (4G) | 17.3 Mbps | 86% of carrier uplink |
| WireGuard tunnel (DERP) | 7.8 Mbps | Relay fallback |
| Photo upload (LAN tunnel) | 6.3 MB/s | Bottleneck: Garage SQLite |
| Photo upload (mobile tunnel) | 2.0 MB/s | Bottleneck: carrier uplink |
| Photo upload (DERP) | 1.1 MB/s | Bottleneck: relay overhead |
| Tunnel latency (LAN) | 3 ms | Direct peer-to-peer |
| Tunnel latency (mobile) | 46 ms | Hole-punched through CGNAT |
| Tunnel latency (DERP) | 112 ms | Bangalore relay |
| Path switchover time | 5–15 seconds | Automatic, zero lost uploads |
| CPU overhead (tunnel active) | < 1% | Kernel WireGuard |
| Temperature impact | +1°C | 47→48°C idle |

---

## Known Issues and Carry-Forward

| Issue | Severity | Planned Resolution |
|---|---|---|
| No HTTPS (plain HTTP through tunnel) | HIGH | Week 06: Caddy reverse proxy |
| Museum buffers entire objects in memory | HIGH | Increase memory limit for 4K video |
| Museum image uses floating `:latest` tag | HIGH | Pin to digest when available |
| Tailscale key expiry (default 180 days) | MEDIUM | Enable key rotation or disable expiry |
| No notification system for alerts | MEDIUM | Week 06+: webhook or push notification |
| Tailscale control plane dependency | LOW | Headscale migration path documented in ADR-004 |

---

## Lessons Learned

1. **NAT traversal is a solved problem.** Tailscale's STUN/ICE hole-punching established direct UDP tunnels through dual CGNAT in under 5 seconds. The technology is mature and reliable. The barrier to self-hosting isn't NAT anymore — it's knowledge.

2. **The tunnel is never the bottleneck.** In every test (LAN, mobile, DERP), the limiting factor was either the application (Garage SQLite WAL) or the network (carrier uplink). WireGuard's kernel-level crypto adds microseconds, not milliseconds.

3. **DERP relay is good enough.** The worst-case path (112 ms, 1.1 MB/s) is slower but functional. Background photo backup doesn't need low latency. It needs reliability. DERP provides reliability.

4. **One URL everywhere.** Using the Tailscale IP (or MagicDNS hostname) as the app's server URL eliminates the "works at home, breaks everywhere else" problem. The same URL works on LAN, mobile, hotel WiFi, and corporate networks.

5. **Gate evidence should be assembled early.** Writing the evidence package on Day 35 (three days before the gate) gave time to verify every claim and run the full demo scenario. Assembling evidence on the gate day itself invites corner-cutting.

---

*Week 05 complete. Gate A passed. Week 06: Caddy HTTPS reverse proxy.*
