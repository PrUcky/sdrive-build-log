# Tailscale & WireGuard Mesh Architecture

This document details the network transport layer used by `sdrive` to achieve secure, zero-configuration remote access across Carrier-Grade NAT (CGNAT) without router port forwarding.

---

## 1. The CGNAT & NAT Traversal Problem

Traditional home server hosting requires:
1. A unique, publicly routable IPv4 address assigned by the ISP.
2. Manually configured Port Forwarding rules on the home router (e.g. mapping public port 443 to internal IP `192.168.1.150`).
3. Dynamic DNS (DDNS) daemons to track changing public IP addresses.

### Why this fails for modern home appliances:
- **Carrier-Grade NAT (CGNAT):** Most residential fiber and 5G ISPs share a single public IPv4 address among hundreds of subscribers. Inbound port forwarding is mathematically impossible.
- **Security Attack Surface:** Forwarding raw ports exposes the host directly to automated Shodan port scanners and zero-day exploit attempts.

---

## 2. WireGuard Overlay & STUN/ICE Hole Punching

Tailscale creates an encrypted peer-to-peer **WireGuard mesh overlay** (`tailscale0` virtual network adapter) on top of the physical Ethernet interface.

```
[ Mobile Phone (Cellular 5G) ]
         │
         ├── 1. Discover Public Endpoint via STUN ──> [ Tailscale DERP Map ]
         │                                                    │
         └── 2. Direct P2P UDP Hole Punching <────────────────┘
         │
[ Tailscale WireGuard Encrypted Tunnel (ChaCha20-Poly1305) ]
         │
[ Radxa ROCK 3C Appliance (tailscale0: 100.64.0.10) ]
```

### Key Mechanics:
1. **STUN (Session Traversal Utilities for NAT):** Both the phone and the board contact Tailscale's coordination server to discover their public-facing UDP endpoints and NAT mapping behaviors (full cone, restricted cone, or symmetric NAT).
2. **Direct Peer-to-Peer UDP Tunnels:** In over 90% of connections, Tailscale successfully negotiates direct UDP hole-punching. Traffic flows directly between phone and board with zero intermediate proxy latency.
3. **DERP Relay Fallback:** If both sides sit behind strict symmetric NATs, traffic falls back to encrypted DERP (Designated Encrypted Relay for Packets) relay servers. Even when relayed, packets remain end-to-end encrypted with WireGuard public keys; DERP servers cannot inspect payload bytes.

---

## 3. MTU & Clamping Considerations

Standard Ethernet frames enforce a Maximum Transmission Unit (MTU) of **1500 bytes**.

WireGuard encapsulates original IP packets inside UDP datagrams, introducing **60 to 80 bytes of encapsulation overhead** (20 bytes IP header + 8 bytes UDP header + 32 bytes WireGuard header + 16 bytes auth tag).

- **`tailscale0` Interface MTU:** **1280 bytes** (the minimum MTU guaranteed by the IPv6 specification).
- **TCP MSS Clamping:** Linux kernel automatically clamps TCP Maximum Segment Size (MSS) on `tailscale0` to $1280 - 40 = 1240\text{ bytes}$, completely eliminating packet fragmentation stalls during multi-megabyte photo uploads over mobile networks.
