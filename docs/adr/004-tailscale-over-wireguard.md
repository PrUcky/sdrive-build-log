# ADR-004: Tailscale Over Raw WireGuard for Overlay Networking

**Status:** Accepted  
**Date:** 2026-09-29  
**Deciders:** Pratyush Chaudhary  

---

## Context

The sdrive appliance must be reachable from outside the local network. The ISP uses Carrier-Grade NAT (CGNAT), which makes traditional port forwarding and dynamic DNS impossible. We need a solution that:

1. Works through CGNAT, double-NAT, and restrictive firewalls
2. Requires no inbound port openings on the router
3. Provides end-to-end encryption between the phone and the appliance
4. Has minimal resource overhead on the ARM64 board
5. Works on mobile data, hotel WiFi, and corporate networks

## Decision

Use **Tailscale** (managed WireGuard mesh) instead of raw WireGuard, a traditional VPN server (OpenVPN, IPsec), or a reverse tunnel (ngrok, Cloudflare Tunnel).

## Rationale

### Raw WireGuard

WireGuard is the underlying protocol, and it's excellent: fast, simple, small codebase, strong cryptography (Curve25519, ChaCha20-Poly1305, BLAKE2s). But raw WireGuard doesn't solve NAT traversal. At least one peer must have a reachable endpoint. With CGNAT on the ISP side, the ROCK 3C has no reachable endpoint. Configuring raw WireGuard would require:

- A VPS with a public IP to act as a relay (monthly cost, additional infrastructure)
- Manual key exchange for every new device
- Manual endpoint configuration updates when IPs change

### Traditional VPN (OpenVPN, IPsec)

These require a server with a public IP, which we don't have behind CGNAT. They're also heavier: OpenVPN runs in userspace with significant CPU overhead, and IPsec is complex to configure. Neither offers the zero-configuration peer discovery that Tailscale provides.

### Reverse Tunnel (ngrok, Cloudflare Tunnel)

These work through CGNAT but introduce a third-party proxy in the data path. Every photo upload would transit through ngrok/Cloudflare servers before reaching the appliance. This adds latency, bandwidth costs, and a dependency on a third-party service's availability and privacy policy.

### Tailscale

Tailscale wraps WireGuard with automated NAT traversal:

| Feature | Raw WireGuard | Tailscale |
|---|---|---|
| CGNAT traversal | ❌ Needs public IP | ✅ STUN/ICE hole-punching |
| Key exchange | Manual per-peer | Automatic via control plane |
| Peer discovery | Manual IPs | Automatic via coordination server |
| MagicDNS | ❌ | ✅ `sdrive.tail*.ts.net` |
| Relay fallback | ❌ | ✅ DERP servers (encrypted) |
| Kernel WireGuard | ✅ | ✅ (uses same kernel module) |
| Memory overhead | ~5 MB (kernel) | ~24 MB (daemon + kernel) |
| Monthly cost | Free | Free (up to 100 devices) |

The control plane is managed by Tailscale Inc., but the data plane is peer-to-peer WireGuard. Photos travel directly between the phone and the ROCK 3C — they don't transit Tailscale's infrastructure (except when direct connection fails, in which case they relay through DERP servers, still encrypted end-to-end).

## Consequences

### Positive
- Works through CGNAT without any router configuration
- Zero-configuration peer setup: scan a QR code on the phone, authenticate, done
- Direct peer-to-peer when possible, encrypted relay when necessary
- 24 MB memory overhead (0.6% of available RAM)
- Stable Tailscale IPs persist across network changes
- MagicDNS provides human-readable hostnames

### Negative
- Dependency on Tailscale's coordination server (outage = no new connections)
- Managed service: Tailscale Inc. can see the network topology (not the traffic)
- Free tier limited to 100 devices and 3 users (sufficient for home use)
- Phone must run the Tailscale app (VPN consent required on Android)

### Neutral
- Same WireGuard encryption (Curve25519 + ChaCha20-Poly1305) as raw WireGuard
- Same kernel-level packet processing as raw WireGuard
- Open-source clients (Tailscale's client code is Apache-2.0)

## Alternatives Considered

1. **Raw WireGuard + VPS relay:** Works but adds monthly cost and infrastructure complexity.
2. **Cloudflare Tunnel:** Works through CGNAT but proxies all traffic through Cloudflare.
3. **ZeroTier:** Similar to Tailscale but less mature, more complex networking model.
4. **Headscale (self-hosted Tailscale control plane):** Eliminates Tailscale Inc. dependency but adds significant operational complexity. Could be a future migration if privacy requirements change.

---

*This decision enables Gate A: embedded network proof by October 4, 2026.*
