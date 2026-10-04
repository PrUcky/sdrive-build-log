# ADR-005: Caddy for TLS Termination

**Status:** Accepted  
**Date:** 2026-10-06  
**Deciders:** Pratyush Chaudhary  

---

## Context

With Tailscale providing the network overlay (ADR-004), the appliance is reachable from anywhere. However, the Tailscale tunnel transports plain HTTP. We need a reverse proxy to terminate TLS (HTTPS) in front of the Museum backend to provide defense-in-depth, cryptographic identity verification, and compatibility with modern app security requirements.

The reverse proxy must:
1. Be extremely lightweight (running alongside Postgres, Garage, and Museum on a 4 GB board)
2. Support mounting externally provisioned Let's Encrypt certificates (from Tailscale's DNS-01 challenge)
3. Handle large file uploads (500+ MB videos) without buffering them entirely in memory
4. Be memory-safe (written in a language immune to buffer overflows)

## Decision

Use **Caddy** as the TLS-terminating reverse proxy instead of NGINX, Traefik, or HAProxy.

## Rationale

### NGINX

NGINX is the industry standard and uses very little memory (often < 10 MB). However, it is written in C and historically susceptible to memory corruption vulnerabilities (buffer overflows, use-after-free). Since the reverse proxy is the only component exposed to the Tailnet, memory safety is a high priority. NGINX's configuration syntax for modern security headers and TLS 1.3 enforcement is also notoriously verbose.

### Traefik

Traefik is written in Go (memory-safe) and excels at dynamic container discovery. However, it is heavily geared toward complex Kubernetes or Swarm clusters. For a static 3-container Docker Compose stack, Traefik's dynamic routing overhead is unnecessary. Its configuration (via Docker labels or YAML) is complex for a simple single-endpoint reverse proxy.

### Caddy

Caddy is written in Go (memory-safe) and is designed specifically for ease of use.
1. **Memory Safety:** Go protects against the buffer overflows that plague C proxies.
2. **Simplicity:** The Caddyfile is incredibly terse. Enforcing HSTS, TLS 1.3, and security headers takes just a few lines.
3. **Resource Footprint:** With automatic ACME disabled (since Tailscale provisions the certs), Caddy sits at ~25-30 MB of RAM.
4. **Streaming:** Caddy's `reverse_proxy` directive streams request bodies directly to the backend by default, which is critical for large video uploads.

While Caddy's signature feature is automatic Let's Encrypt provisioning via HTTP-01/TLS-ALPN-01, we cannot use that feature because the appliance is behind CGNAT and has no public inbound ports. Instead, we use Tailscale to provision the certificates via DNS-01 and configure Caddy to use those static cert files with `auto_https off`.

## Consequences

### Positive
- **Security:** The only exposed HTTP listener is memory-safe.
- **Simplicity:** The entire routing and security header configuration fits in ~40 lines of a readable Caddyfile.
- **Performance:** HTTP/2 and TLS 1.3 are enabled by default.

### Negative
- **Memory Overhead:** Uses slightly more memory (~30 MB) than NGINX (~10 MB).
- **Certificate Reloads:** Because Tailscale provisions the certificates outside of Caddy, Caddy does not automatically know when they are renewed. A cron job or script will be needed to reload Caddy gracefully when Tailscale rotates the certificates.

## Alternatives Considered

1. **Stunnel / Ghostunnel:** Pure TLS proxies. Very lightweight, but they lack the ability to set HTTP security headers (HSTS, X-Frame-Options) or enforce request body size limits at the HTTP layer.
2. **Envoy:** Powerful and memory-safe (C++ but heavily audited/fuzzed), but vastly too complex for a single-node home appliance.

---

*This decision finalizes the perimeter security architecture for Week 06.*
