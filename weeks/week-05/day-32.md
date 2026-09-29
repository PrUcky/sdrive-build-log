# Day 32: Tailscale and the Overlay Network — Punching Through CGNAT

*September 29, 2026*

Week 05. Gate A is October 4 — six days from now. The gate requires embedded network proof: the phone must be able to reach the sdrive appliance from outside the local network, through CGNAT, through hotel WiFi, through mobile data. No port forwarding. No dynamic DNS. No exposed attack surface. Just a WireGuard tunnel that works everywhere.

Today I installed Tailscale on the ROCK 3C, understood the architecture that makes it work, and proved the first tunnel.

## The Problem: CGNAT

My ISP uses Carrier-Grade NAT. The router's WAN IP isn't a real public IP — it's a `100.64.x.x` address in the shared CGNAT space. I discovered this back in Week 02 when `traceroute` showed the first hop was a CGNAT gateway, not the open internet. This means:

- **Port forwarding is impossible.** I can't open port 8080 on the router because the router doesn't have a public IP. There are multiple NAT layers between my router and the internet.
- **Dynamic DNS is useless.** Even if I registered a domain pointing at my WAN IP, that IP is behind CGNAT and unreachable from the public internet.
- **UPnP can't help.** UPnP only controls the local router's NAT, not the ISP's CGNAT gateway.

Every traditional remote access method fails. This is why the roadmap specifies Tailscale: it's designed to work through CGNAT, double-NAT, and restrictive firewalls by establishing outbound-only connections that don't require any inbound port openings.

## How Tailscale Works

Tailscale is a mesh VPN built on WireGuard, but the distinction between Tailscale and raw WireGuard matters:

**WireGuard** is a kernel-level VPN protocol. It's fast, simple, and cryptographically sound (Curve25519, ChaCha20-Poly1305, BLAKE2s). But raw WireGuard requires you to configure each peer's public key and endpoint IP manually. It doesn't solve NAT traversal — at least one peer needs a reachable IP.

**Tailscale** adds three things on top of WireGuard:

1. **A coordination server** (the Tailscale control plane) that distributes peer public keys and network maps. This replaces manual key exchange.

2. **NAT traversal via STUN/ICE** — Tailscale's netcheck protocol discovers the best path between peers. If both peers can create a direct UDP connection (hole-punching through NAT), they do. If not, traffic relays through Tailscale's DERP (Designated Encrypted Relay for Packets) servers.

3. **MagicDNS** — each device gets a stable hostname on the tailnet (e.g., `sdrive.tail12345.ts.net`) that resolves to its Tailscale IP regardless of the underlying network.

The architecture means the ROCK 3C doesn't need a public IP. It doesn't need port forwarding. It doesn't need the ISP's cooperation. It opens an outbound connection to the Tailscale coordination server, receives its peer configuration, and establishes a WireGuard tunnel. The tunnel works from behind CGNAT because it's an outbound UDP connection — every NAT gateway in the world allows outbound UDP.

## Installing Tailscale on ARM64

Tailscale provides an official install script:

```bash
root@sdrive:~# curl -fsSL https://tailscale.com/install.sh | sh
...
Installation complete.
tailscale version 1.72.1
  go version: go1.22.4
```

The installer added the Tailscale APT repository, installed the `tailscale` and `tailscaled` packages (the CLI and the daemon), and enabled the systemd service. The daemon is written in Go and ships as a static binary — no runtime dependencies on the ARM64 board.

I verified the daemon started:

```bash
root@sdrive:~# systemctl status tailscaled
● tailscaled.service - Tailscale node agent
     Loaded: loaded (/lib/systemd/system/tailscaled.service; enabled)
     Active: active (running) since Mon 2026-09-29 06:14:22 IST
   Main PID: 4821 (tailscaled)
     Memory: 24.3 MiB
```

24 MB of memory for the Tailscale daemon. Minimal footprint on the 4 GB board.

## Authenticating and Joining the Tailnet

I brought the node up and authenticated:

```bash
root@sdrive:~# tailscale up

To authenticate, visit:
  https://login.tailscale.com/a/abc123def456
```

I opened the URL on my desktop, authenticated with the Tailscale account, and approved the node. Within seconds:

```bash
root@sdrive:~# tailscale status
100.100.42.17   sdrive          linux   -
100.100.89.3    desktop-pc      windows -
100.100.64.11   pixel-phone     android -
```

Three devices on the tailnet: the ROCK 3C (`100.100.42.17`), my desktop, and my phone. Each has a stable Tailscale IP in the `100.x.y.z` range. These IPs persist across reboots, network changes, and location changes.

## The First Tunnel Test

I tested connectivity from my desktop to the ROCK 3C via the Tailscale tunnel:

```bash
C:\> ping 100.100.42.17
Pinging 100.100.42.17 with 32 bytes of data:
Reply from 100.100.42.17: bytes=32 time=3ms TTL=64
Reply from 100.100.42.17: bytes=32 time=2ms TTL=64
```

3 ms latency over the tunnel. Both devices are on the same LAN, so this is a direct peer-to-peer WireGuard connection — no relay involved. Tailscale's STUN hole-punching detected that both peers are on the same network and established a direct path.

I then tested the Museum health endpoint through the tunnel:

```bash
C:\> curl -s http://100.100.42.17:8080/health
{"status":"ok"}
```

Museum is reachable at `100.100.42.17:8080` via the WireGuard tunnel. The phone could theoretically connect to this address instead of `192.168.1.150:8080` and the backup would work through the tunnel.

But this is the easy test — same LAN, direct path. The real test is from outside the network.

## Simulating Remote Access

I can't physically leave my house to test remote access from a coffee shop. But I can simulate it. I disconnected my phone from WiFi, forcing it onto mobile data (which goes through the carrier's own CGNAT), and tested:

```bash
# On phone (mobile data, 4G LTE):
$ ping 100.100.42.17
PING 100.100.42.17: 56 data bytes
64 bytes from 100.100.42.17: icmp_seq=0 ttl=64 time=48ms
64 bytes from 100.100.42.17: icmp_seq=1 ttl=64 time=42ms
```

48 ms from mobile data to the ROCK 3C in my house. The packet traveled: phone → carrier tower → carrier CGNAT → internet → Tailscale DERP relay (or direct, depending on NAT type) → ISP CGNAT → router → ROCK 3C. Or more likely, given the low latency, Tailscale managed to hole-punch through both CGNAT layers and establish a direct WireGuard tunnel.

I verified which path was used:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via 10.45.72.18:41641 in 44ms
```

The `via` address shows a direct UDP connection to the phone's carrier-assigned IP, not a DERP relay. Tailscale successfully hole-punched through both CGNAT layers. The connection is direct, encrypted, and fast.

I then hit the Museum endpoint from the phone's browser over mobile data:

```
http://100.100.42.17:8080/health
{"status":"ok"}
```

The appliance is reachable from mobile data. Through CGNAT. Without port forwarding. Without a public IP. Without exposing any ports to the internet.

## UFW Integration

I updated the UFW rules to allow Tailscale traffic:

```bash
root@sdrive:~# ufw allow in on tailscale0
Rule added

root@sdrive:~# ufw status
Status: active
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       192.168.1.0/24
8080/tcp                   ALLOW       192.168.1.0/24
Anywhere on tailscale0     ALLOW       Anywhere
```

The `tailscale0` interface is the virtual WireGuard interface. By allowing all traffic on this interface, any device on my tailnet can reach any service on the ROCK 3C — but only if they're authenticated on the tailnet. The tailnet IS the access control. Unauthenticated devices can't generate valid WireGuard handshakes, so they can't reach the `tailscale0` interface at all.

## Attack Surface Assessment

I ran the socket audit with the new Tailscale interface:

```bash
root@sdrive:~# ss -tulnp
Netid  State  Local Address:Port   Process
tcp    LISTEN 0.0.0.0:22           sshd
tcp    LISTEN 0.0.0.0:8080         docker-proxy (museum)
udp    LISTEN 0.0.0.0:41641        tailscaled
```

One new listener: `tailscaled` on UDP port 41641. This is the WireGuard endpoint. The port is only useful if you have a valid Tailscale identity — WireGuard silently drops packets from unknown peers. There's no TCP handshake, no banner, no response to port scans. From the internet's perspective, port 41641 is a black hole.

The attack surface has grown by exactly one UDP listener that is cryptographically invisible to unauthorized peers. This is the best possible security posture for remote access.

## Resource Impact

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 380 MB / 3788 MB (10%)
  Disk:   5.2G / 458G (1%)
  Load:   0.12 0.08 0.05
  CPU:    49°C
```

Memory increased by 24 MB (Tailscale daemon). From 356 MB to 380 MB. CPU and temperature unchanged. The WireGuard tunnel is handled by the Linux kernel's built-in WireGuard module — it's not userspace packet processing, so the overhead is near-zero even under sustained tunnel traffic.

Gate A requires embedded network proof by October 4. Today's test — Museum responding to `curl` from mobile data via the Tailscale tunnel — is the foundation of that proof. But the gate requires the phone app to actually connect and back up photos through the tunnel, not just `curl`. That's the next step.

Tomorrow: configuring the Ente app to use the Tailscale endpoint and uploading the first photo through the tunnel.
