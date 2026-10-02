# Punching Through CGNAT: How a WireGuard Overlay Makes a Home Server Reachable From Anywhere

*By Pratyush Chaudhary · October 2, 2026 · 11 min read*

---

## 1. The CGNAT Wall

The sdrive appliance sits on a desk in my house, connected to a consumer ISP. It runs three containers (PostgreSQL, Garage, Museum) serving an encrypted photo backup API. On the local network, the phone connects to `192.168.1.150:8080` and backs up photos in half a second each. But the moment you leave the house, the connection breaks.

The reason is CGNAT — Carrier-Grade NAT. My ISP doesn't give me a public IP address. The router's WAN interface has a `100.64.x.x` address in the shared CGNAT space. Between my router and the open internet, there's at least one additional NAT gateway operated by the ISP. Port forwarding is impossible. Dynamic DNS is useless. UPnP controls only the local router, not the ISP's gateway.

This week, I solved CGNAT with a WireGuard overlay network. The appliance is now reachable from mobile data, hotel WiFi, and corporate networks — without exposing a single port to the public internet.

---

## 2. Why Traditional Solutions Fail

**Port forwarding** requires a public IP on the router's WAN interface. With CGNAT, I don't have one.

**Dynamic DNS** maps a domain name to your WAN IP. But if that IP is behind CGNAT, the domain points to an unreachable address.

**VPN servers** (OpenVPN, IPsec) need a reachable endpoint. Same problem — without a public IP, no one can connect to the VPN.

**Reverse tunnels** (ngrok, Cloudflare Tunnel) work through CGNAT by establishing outbound connections to a relay service. But every photo upload transits through the relay's servers, adding latency and a dependency on a third-party service.

---

## 3. The WireGuard + Tailscale Solution

WireGuard is a kernel-level VPN protocol: fast, simple, and cryptographically sound. But raw WireGuard doesn't solve NAT traversal. Tailscale adds the missing pieces: automated NAT traversal via STUN/ICE hole-punching, a coordination server for key exchange, and DERP relay servers for when direct connections fail.

The architecture:

- **Managed coordination** — Tailscale's control plane distributes peer public keys and network maps. It never sees the actual traffic.
- **Direct data path** — When possible, devices establish peer-to-peer WireGuard tunnels. Photos travel directly between the phone and the ROCK 3C.
- **Encrypted relay fallback** — When direct connection fails (aggressive firewalls, symmetric NAT), traffic relays through DERP servers. Still encrypted end-to-end with WireGuard.

Installation was a single command:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

The appliance got a stable IP (`100.100.42.17`) that persists across reboots and network changes. The phone app connects to this IP from anywhere.

---

## 4. The Three Connection Paths

I benchmarked every path the tunnel can take:

| Path | How It Works | Bandwidth | Latency | Photo Upload |
|---|---|---|---|---|
| **LAN Direct** | Both on same WiFi, direct peer-to-peer | 382 Mbps | 3 ms | 6.3 MB/s |
| **Mobile Direct** | Hole-punched through dual CGNAT | 17.3 Mbps | 46 ms | 2.0 MB/s |
| **DERP Relay** | Relayed through Tailscale's server | 7.8 Mbps | 112 ms | 1.1 MB/s |

The critical insight: **WireGuard is never the bottleneck.** On LAN, the bottleneck is Garage's SQLite WAL (application-level serialization). On mobile, it's the carrier's uplink cap. Through DERP, it's the relay hop overhead. The tunnel encryption (ChaCha20-Poly1305 in the Linux kernel) adds microseconds, not milliseconds.

---

## 5. The DERP Fallback Test

DERP (Designated Encrypted Relay for Packets) is Tailscale's fallback for when direct connections fail. I tested it by blocking the direct UDP path with a firewall rule:

```bash
ufw deny from 10.45.72.18  # Block phone's carrier IP
```

Tailscale detected the failure within seconds and automatically switched to the DERP relay in Bangalore. Latency jumped from 46 ms to 112 ms. Upload speed dropped from 2.0 MB/s to 1.1 MB/s. But the photos still uploaded correctly, decrypted correctly on the receiving device, and the gallery showed all of them.

When I removed the firewall rule, Tailscale automatically switched back to the direct path within 30 seconds. No manual intervention. No restart.

---

## 6. Security: The Invisible Server

The traditional approach to remote access — port forwarding — exposes services to the entire internet. Port scanners find them. Bots probe them. A single vulnerability in the exposed service means compromise.

With Tailscale, the attack surface is:

- **Zero public TCP ports.** Museum isn't reachable from the internet.
- **One UDP port** (41641) that runs WireGuard. WireGuard silently drops packets from unknown peers. There's no TCP handshake, no banner, no response. Port scanners see nothing.
- **Cryptographic access control.** Only devices with valid Tailscale identities (Curve25519 key pairs authenticated through the control plane) can establish WireGuard handshakes.

The server is functionally invisible to the public internet. It can only be reached by authenticated tailnet members.

---

## 7. The Resource Cost

Tailscale added 24 MB of memory (the `tailscaled` Go daemon) and one UDP listener. The WireGuard encryption runs in the Linux kernel and adds no measurable CPU overhead:

| Metric | Before Tailscale | After Tailscale |
|---|---|---|
| Memory | 356 MB | 380 MB (+24 MB) |
| CPU temp | 48°C | 49°C (+1°C) |
| Load avg | 0.08 | 0.12 (+0.04) |
| Network listeners | 2 | 3 (+1 UDP) |

On a 4 GB board, 24 MB is 0.6% of available RAM. The appliance barely notices Tailscale is running.

---

## 8. The Demo Scenario

The proof that matters:

1. Phone A is on mobile data (4G LTE, behind carrier CGNAT)
2. Phone A takes a photo and backs it up through the Tailscale tunnel
3. The encrypted photo travels through WireGuard to the ROCK 3C
4. Garage stores the encrypted blob on the USB SSD
5. Phone B (also on Tailscale) opens the gallery
6. Phone B sees the photo, taps it, and views the full resolution
7. The photo is identical to the original

Two phones, two CGNAT layers, one appliance, end-to-end encryption, and the photo arrives intact. This is Gate A: embedded network proof.

---

## 9. What's Next

The tunnel works. The photos travel. But the connection is plain HTTP — `http://100.100.42.17:8080`. Week 06 adds Caddy as a TLS-terminating reverse proxy, serving HTTPS with a Let's Encrypt certificate provisioned through Tailscale. The URL will become `https://sdrive.tail12345.ts.net` — encrypted transport on top of encrypted tunnel on top of encrypted photos. Defense in depth.

---

*This article is part of the **`sdrive` Build Log** — a 12-week public engineering series documenting the ground-up development of an end-to-end encrypted home photo backup appliance. Track the daily commits on GitHub: [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
