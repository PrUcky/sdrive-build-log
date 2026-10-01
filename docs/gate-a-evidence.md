# Gate A: Embedded Network Proof

**Gate Date:** October 4, 2026  
**Status:** ✅ **PASSED** (evidence assembled October 1, 2026)  
**Requirement:** The phone must reach the sdrive appliance from outside the local network, through CGNAT, and perform a complete photo upload/download cycle through the embedded overlay network.

---

## Evidence Summary

| # | Criterion | Result | Evidence Source |
|---|---|---|---|
| 1 | Tailscale installed and running on ROCK 3C | ✅ PASS | Day 32: v1.72.1, systemd-managed, 24 MB |
| 2 | Stable Tailscale IP assigned | ✅ PASS | Day 32: `100.100.42.17` persists across reboots |
| 3 | Direct tunnel through ISP CGNAT | ✅ PASS | Day 32: hole-punched, `via 10.45.72.18:41641` |
| 4 | Photo upload through tunnel (same LAN) | ✅ PASS | Day 33: 0.5s per 4.2 MB photo, 3 ms latency |
| 5 | Photo upload through tunnel (mobile data) | ✅ PASS | Day 33: 1.8s per photo, 46 ms latency |
| 6 | Photo download through tunnel (mobile data) | ✅ PASS | Day 33: 1.2s full-res, 300 ms thumbnails |
| 7 | Multi-device: phone A uploads, phone B views | ✅ PASS | Day 33: same account, both on Tailscale |
| 8 | Account isolation: separate accounts can't see each other | ✅ PASS | Day 33: zero cross-leak verified |
| 9 | Tunnel throughput benchmarked (3 paths) | ✅ PASS | Day 34: 382 / 17.3 / 7.8 Mbps |
| 10 | DERP relay fallback works when direct fails | ✅ PASS | Day 34: 112 ms, 1.1 MB/s, photos intact |
| 11 | Automatic path recovery (WiFi → mobile → WiFi) | ✅ PASS | Day 34: 5–15s switchover, zero lost uploads |

**11 / 11 criteria passed.**

---

## Architecture Proven

```
Phone (anywhere)                              ROCK 3C (home)
┌──────────────────┐    WireGuard Tunnel     ┌──────────────────┐
│  Ente App        │─────────────────────│  Museum :8080     │
│  Tailscale VPN   │  (direct or DERP)    │  Garage :3900     │
│  100.100.64.11   │                      │  PostgreSQL :5432 │
└──────────────────┘                      │  100.100.42.17   │
                                           └──────────────────┘

Stack: Ente Museum + Garage + PostgreSQL on Docker
Network: Tailscale (managed coordination, embedded WireGuard)
Path: Direct where possible, encrypted DERP relay as fallback
Security: Zero ports exposed to public internet
```

---

## Throughput Evidence

| Connection Path | Tunnel Bandwidth | Photo Upload Rate | Latency | Bottleneck |
|---|---|---|---|---|
| LAN Direct (WiFi) | 382 Mbps | 6.3 MB/s | 3 ms | Garage SQLite WAL |
| Mobile Direct (4G) | 17.3 Mbps | 2.0 MB/s | 46 ms | Carrier uplink |
| DERP Relay (fallback) | 7.8 Mbps | 1.1 MB/s | 112 ms | Relay overhead |

In every scenario, the WireGuard tunnel is NOT the bottleneck.

---

## Security Posture

| Attack Surface | Status |
|---|---|
| Public-facing TCP ports | **Zero** |
| Public-facing UDP ports | **Zero** (WireGuard drops unknown peers silently) |
| Port forwarding on router | **Not required** |
| Public IP required | **No** (works through CGNAT) |
| Traffic encryption | WireGuard (Curve25519 + ChaCha20-Poly1305) |
| Photo encryption | XChaCha20-Poly1305 (client-side, zero-knowledge) |
| Server access control | Tailnet membership (cryptographic identity) |

---

## Resource Impact

| Metric | Before Tailscale | After Tailscale | Delta |
|---|---|---|---|
| System memory | 356 MB | 380 MB | +24 MB (+0.6%) |
| CPU load (idle) | 0.08 | 0.12 | +0.04 |
| CPU temperature | 48°C | 49°C | +1°C |
| Network listeners | 2 (SSH, Museum) | 3 (+WireGuard UDP) | +1 |
| Disk usage | 0 MB | 0 MB | Stateless |

---

## Failure Modes Tested

| Scenario | Behavior | Recovery |
|---|---|---|
| Direct path blocked | Auto-switch to DERP relay | ~5 seconds |
| DERP relay unavailable | Connection pauses, retries | Automatic when relay returns |
| WiFi → mobile transition | Brief pause, resumes upload | 5–15 seconds |
| Mobile → WiFi transition | Upgrades to faster direct path | 5–15 seconds |
| Tailscale daemon restart | WireGuard tunnel re-established | ~3 seconds |
| Board reboot | tailscaled auto-starts, re-authenticates | ~30 seconds |

---

## Verification Commands

```bash
# Verify Tailscale is running
tailscale status

# Test tunnel connectivity
tailscale ping pixel-phone

# Check connection path (direct vs DERP)
tailscale netcheck

# Test Museum through tunnel
curl -s http://100.100.42.17:8080/health

# Full health check
./scripts/sdrive-tailscale-health.sh
```

---

## Daily Log References

| Day | Date | Topic | Key Evidence |
|---|---|---|---|
| 32 | Sep 29 | Tailscale installation | Tunnel up, CGNAT bypassed, UFW integrated |
| 33 | Sep 29 | First photo through tunnel | Upload/download from mobile data, multi-device |
| 34 | Sep 30 | Throughput benchmarks | 3 paths benchmarked, DERP fallback, path recovery |
| 35 | Oct 1 | Gate A evidence (this doc) | Evidence package assembled |

---

*Gate A: Embedded network proof — **PASSED**. The sdrive appliance is reachable from any network through Tailscale's WireGuard overlay, with zero exposed ports, automatic path selection, and encrypted relay fallback.*
