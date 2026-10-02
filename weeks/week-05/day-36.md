# Day 36: MagicDNS and the HTTPS Roadmap — Names Instead of Numbers

*October 2, 2026*

Two days until Gate A, but the evidence is already assembled. Today I enabled Tailscale's MagicDNS so the appliance gets a human-readable hostname on the tailnet, explored Tailscale's HTTPS certificate provisioning, and mapped out the Caddy reverse proxy architecture for Week 06.

## MagicDNS: From IP to Name

Until now, the Ente app connects to `http://100.100.42.17:8080`. That works, but nobody wants to type an IP address. MagicDNS assigns DNS names to every device on the tailnet:

```bash
root@sdrive:~# tailscale status
100.100.42.17   sdrive          linux   -
100.100.89.3    desktop-pc      windows idle
100.100.64.11   pixel-phone     android active; direct
```

The hostname `sdrive` is already assigned. I enabled MagicDNS in the Tailscale admin console and verified:

```bash
root@sdrive:~# tailscale dns status
MagicDNS: enabled
DNS suffix: tail12345.ts.net

root@sdrive:~# dig +short sdrive.tail12345.ts.net
100.100.42.17
```

The appliance is now reachable at `sdrive.tail12345.ts.net`. From any device on the tailnet:

```bash
# From desktop:
C:\> curl -s http://sdrive.tail12345.ts.net:8080/health
{"status":"ok"}

# From phone (mobile data):
$ curl -s http://sdrive.tail12345.ts.net:8080/health
{"status":"ok"}
```

Same result, human-readable URL. The DNS resolution happens inside Tailscale's local DNS resolver — it never touches the public DNS system. The hostname `sdrive.tail12345.ts.net` only resolves for authenticated tailnet members.

## Tailscale HTTPS Certificates

Tailscale can provision TLS certificates for MagicDNS hostnames via Let's Encrypt. This means the appliance could serve HTTPS at `https://sdrive.tail12345.ts.net` without running its own certificate authority or exposing port 443 to the internet.

I explored this path:

```bash
root@sdrive:~# tailscale cert sdrive.tail12345.ts.net
Wrote private key to sdrive.tail12345.ts.net.key
Wrote certificate to sdrive.tail12345.ts.net.crt
```

Tailscale generated a valid Let's Encrypt certificate and private key. The certificate chain is publicly trusted — browsers and apps will accept it without custom CA configuration. The provisioning uses Tailscale's DNS-01 ACME challenge, so no inbound port 80 or 443 is needed.

But there's a catch: Museum doesn't natively serve HTTPS. It's a Go HTTP server that listens on port 8080 and expects a reverse proxy to handle TLS termination. This is where Caddy comes in.

## The Caddy Architecture for Week 06

Caddy is a Go-based reverse proxy and web server with automatic HTTPS. It obtains and renews TLS certificates without manual intervention. The plan for Week 06:

```
Phone (Ente App)
  │
  │ https://sdrive.tail12345.ts.net (port 443)
  ▼
Caddy (reverse proxy)
  │
  │ TLS termination (Tailscale cert or Caddy auto-cert)
  │ Proxy: http://museum:8080
  ▼
Museum (Go Backend)
  │
  │ Unchanged HTTP backend
  ▼
Garage / PostgreSQL
```

Caddy sits in front of Museum, terminates TLS, and forwards plaintext HTTP to Museum inside the Docker bridge network. Museum doesn't know or care that the connection was encrypted — it sees `http://localhost:8080` requests as usual.

I drafted the Caddy configuration:

```caddyfile
# Caddyfile for sdrive
# Serves HTTPS on the Tailscale interface only

sdrive.tail12345.ts.net {
    reverse_proxy museum:8080

    tls /etc/caddy/certs/sdrive.tail12345.ts.net.crt \
        /etc/caddy/certs/sdrive.tail12345.ts.net.key

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
    }

    log {
        output file /var/log/caddy/access.log {
            roll_size 10mb
            roll_keep 3
        }
    }
}
```

This is a draft — Week 06 will implement, test, and harden it. But the architecture is clear:

1. Caddy listens on port 443 (HTTPS only)
2. TLS uses the Tailscale-provisioned Let's Encrypt certificate
3. Traffic is proxied to Museum on the Docker bridge
4. Security headers prevent common web attacks
5. Access logs are rotation-capped at 30 MB

## The Connection URL Evolution

The app's server URL has evolved through three stages:

| Week | URL | Works Where |
|---|---|---|
| Week 03 | `http://192.168.1.150:8080` | Home WiFi only |
| Week 05 | `http://100.100.42.17:8080` | Anywhere (via Tailscale) |
| Week 06 (planned) | `https://sdrive.tail12345.ts.net` | Anywhere, encrypted |

Each iteration adds reach and security without changing the backend. Museum serves the same HTTP API. The infrastructure around it handles the complexity of remote access and encryption.

## Why HTTPS Matters Even With WireGuard

The Tailscale tunnel already encrypts traffic with WireGuard (ChaCha20-Poly1305). So why add HTTPS on top?

Three reasons:

1. **Defense in depth.** If the WireGuard tunnel is somehow compromised (which would require breaking Curve25519), the TLS layer provides a second encryption envelope. This is a defense-in-depth principle, not paranoia.

2. **Certificate validation.** HTTPS gives the Ente app a way to cryptographically verify it's talking to the real sdrive server, not a man-in-the-middle. The WireGuard tunnel authenticates peers, but the HTTP layer doesn't — without HTTPS, a compromised Tailscale node could theoretically impersonate the Museum API.

3. **App compatibility.** Some features of the Ente app (and modern browsers in general) require HTTPS. Service workers, certain API features, and security contexts assume a secure origin. Plain HTTP may trigger warnings or limitations.

## Resource Planning for Caddy

Caddy is written in Go, similar to Museum. Expected resource impact:

| Metric | Estimated |
|---|---|
| Memory (idle) | ~20–30 MB |
| Memory (active proxy) | ~40–60 MB |
| CPU overhead | < 1% (TLS handshake is the only CPU-intensive operation) |
| Disk | ~30 MB (binary + certs) |
| Container count | 4 (adds 1 to current 3) |

With Caddy added, the total container memory would be approximately 218–248 MB (Postgres 38 + Garage 28 + Museum 122 + Caddy 30). Still well within the 4 GB board's capacity.

## Updated Compose Stack (Draft)

I sketched how the Compose file will evolve in Week 06:

```yaml
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
      - ./certs:/etc/caddy/certs:ro
    depends_on:
      museum:
        condition: service_healthy
    networks:
      - internal
    deploy:
      resources:
        limits:
          memory: 256M
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:size=32M
```

Caddy depends on Museum being healthy before starting. It gets the same hardening treatment: memory limit, no-new-privileges, read-only rootfs. The Tailscale-provisioned certificates are mounted read-only.

This is planning, not implementation. Week 06 will build and test it. But having the architecture mapped out now means Week 06 can focus on execution rather than design.

## System Snapshot

```bash
root@sdrive:~# ./scripts/sdrive-golden-signals.sh
[LATENCY] museum /health: 12ms
[TRAFFIC] Garage objects: 5,540 / SSD: 5.5G
[ERRORS] Container restarts: 0
[SATURATION]
  Memory: 384 MB / 3788 MB (10%)
  Disk:   5.5G / 458G (1%)
  Load:   0.06 0.05 0.02
  CPU:    47°C
```

The board is idle at 47°C, 10% memory, near-zero load. Five days of continuous uptime. Zero container restarts. The system is stable and ready for the gate.

Tomorrow: Week 05 retrospective and the weekly article.
