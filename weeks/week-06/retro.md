# Week 06 Retrospective — The Invisible Server

*October 4 – October 8, 2026 · Days 38–42*

---

## Goal

> Deploy a memory-safe TLS reverse proxy, strip all public ports from backend containers, and enforce a strict Tailnet-only security perimeter.

**Verdict: ACHIEVED.** Caddy deployed, TLS 1.3 enforced, Docker-UFW bypass fixed, and 4-layer security architecture formalized.

---

## Exit Criteria Assessment

| Criterion | Status | Evidence |
|---|---|---|
| Caddy deployed alongside stack | ✅ PASS | Day 38: Added to `docker-compose.yml` |
| TLS 1.3 termination active | ✅ PASS | Day 38: Curl handshake verified |
| Museum port (8080) removed | ✅ PASS | Day 38: Docker bridge isolation |
| Physical LAN traffic dropped | ✅ PASS | Day 39: UFW lockdown script |
| 600MB video streaming tested | ✅ PASS | Day 40: Tuned Caddyfile timeouts |
| Memory limits enforced | ✅ PASS | Day 38: Caddy capped at 256MB |
| Security architecture documented | ✅ PASS | Day 41: `security-architecture.md` |

---

## Milestone Inventory

### Day 38 — Caddy Deployment and TLS Termination
- Removed `8080:8080` from the Museum container.
- Added Caddy `2-alpine` with read-only rootfs and 256MB limit.
- Mounted Tailscale-provisioned Let's Encrypt certificates.
- Verified TLS 1.3 handshake, HTTP/2 ALPN, and strict security headers via `curl`.

### Day 39 — The Firewall Lockdown
- Discovered and mitigated Docker's UFW `FORWARD` chain bypass.
- Wrote `sdrive-firewall.sh` to enforce interface-level rules.
- Local physical interface (`end0`) restricted entirely to SSH (Port 22).
- Verified the server silently drops HTTPS requests from the local LAN.

### Day 40 — Tuning for the Heavy Lifts
- Uploaded a 600 MB 4K video over a slow DERP relay connection.
- Caddy connection dropped at 8 minutes (Slowloris protection).
- Tuned Caddyfile: `max_size 1024MB`, `read_body 10m`, `write 10m`.
- Re-tested 600 MB upload: Succeeded flawlessly in 9m12s with minimal proxy memory overhead.

### Day 41 — Security Architecture Review
- Documented the 4-layer defense-in-depth strategy.
- Layer 1: Tailnet / UFW Stealth.
- Layer 2: Caddy TLS 1.3 Transport.
- Layer 3: Museum JWT Auth / Zero Public Ports.
- Layer 4: Client-side XChaCha20 E2E Encryption.

### Day 42 — Retrospective and Article
- Published Week 06 Retrospective.
- Published Weekly Article: *The Docker-UFW Bypass and the Invisible Server*.

---

## Artifacts Produced

### Scripts
| File | Purpose |
|---|---|
| `scripts/sdrive-firewall.sh` | Interface-level UFW lockdown |

### Documentation
| File | Purpose |
|---|---|
| `docs/adr/005-caddy-tls-termination.md` | Caddy vs NGINX/Traefik decision |
| `docs/security-architecture.md` | 4-layer perimeter definition |

### Configuration
| File | Purpose |
|---|---|
| `config/caddy/Caddyfile` | TLS, headers, timeouts, 1GB limit |
| `compose/docker-compose.yml` | +Caddy, -Museum ports, tmpfs mounts |

---

## Key Performance Numbers

| Metric | Value | Context |
|---|---|---|
| Caddy Memory (Idle) | ~25 MB | Disabling auto-HTTPS saves RAM |
| Caddy Memory (600MB Video) | ~28 MB | Streams body directly to backend |
| Caddy CPU Overhead | < 2% | TLS handshakes only |
| UFW Drop Latency | Timeout | Packets silently dropped, no RST |

---

## Lessons Learned

1. **Docker makes UFW dangerous by default.** If you publish a Docker port (e.g., `443:443`), Docker writes rules to the `DOCKER` iptables chain that preempt UFW's `INPUT` drop rules. To a sysadmin looking at `ufw status`, the port appears blocked. To an attacker, it's wide open. Binding rules to explicit interfaces (`allow in on tailscale0`) is the only clean way to fix this without breaking container DNS.
2. **Reverse proxies hate slow mobile connections.** Default proxy timeouts (often 30-60 seconds) are designed for fast broadband. When a phone uploads a 500 MB video over a spotty cellular connection, it looks exactly like a Slowloris attack. Explicitly increasing `read_body` timeouts to 10+ minutes is mandatory for self-hosted media apps.
3. **Caddy is brilliant for edge appliances.** Written in Go, it eliminates memory corruption fears. Its streaming behavior means an 800 MB video upload uses exactly as much RAM as a 4 MB photo upload.

---

*Week 06 complete. The infrastructure phase is done. Next up: Long-term reliability and Gate B preparation.*
