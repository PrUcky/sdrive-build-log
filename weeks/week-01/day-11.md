# Day 11 — The Mesh and The First Cellular SSH

**Week:** 01 · **Date:** 2026-09-01 · **Hours:** ~6.0

Today was the day the network ceased to be an obstacle. Since Day 01, Carrier-Grade NAT (CGNAT) and home router firewalls have loomed in my architecture diagrams as the primary reason self-hosted cloud replacements fail in the real world. Today, we brought up Tailscale’s WireGuard mesh on the Radxa ROCK 3C and logged into the board over an external 5G cellular connection with zero port forwarding.

## What I actually did

I structured today’s session around three core objectives: deploying the Tailscale daemon on the board, testing out-of-band NAT traversal over cellular data, and benchmarking encrypted WireGuard throughput over the virtual `tailscale0` network interface.

### 1. Provisioning Tailscale on Armbian
I executed our automated setup script (`config/tailscale/tailscale-up.sh`) over our local SSH connection. The script added the official Tailscale Debian Bookworm repository, installed the `tailscaled` daemon, and initiated the node registration handshake:

```bash
sudo tailscale up --hostname="sdrive-node1" --accept-dns=true --ssh=false --reset
```

I authenticated the node through the browser OAuth workflow. Within four seconds, the Tailscale coordination server provisioned the virtual interface `tailscale0`, assigning the board its permanent mesh IPv4 address (`100.64.0.10`) and a routable IPv6 address. 

I verified that MagicDNS was functioning immediately: from my workstation, querying `ping sdrive-node1.ts.net` resolved straight to `100.64.0.10` with a sub-millisecond round-trip time.

### 2. The Cellular Connection Test
This was the moment of truth for the remote access architecture. 

To simulate a real-world scenario where I am away from home and backing up photos over mobile data, I disabled Wi-Fi on my laptop and connected it to my phone’s 5G cellular hotspot. My laptop was now sitting on an external cellular network, while the Radxa ROCK 3C was sitting on my living room switch behind a standard residential router with zero inbound ports forwarded.

I typed the command into my terminal:

```bash
ssh sdrive-admin@sdrive-node1.ts.net
```

I pressed Enter. Within 28 milliseconds, the terminal negotiated the Curve25519 key exchange, verified our Ed25519 administrative key, and dropped me straight into the `sdrive-node1` prompt. 

It was an incredible feeling. There was no dynamic DNS configuration, no fragile router port mapping, no public IP exposure on Shodan, and no router UPnP hacks. The connection simply worked, as if the board were sitting on a physical cable directly plugged into my laptop.

### 3. Inspecting the WireGuard Route (`tailscale ping`)
I wanted to verify whether the connection was flowing directly peer-to-peer or if it was bouncing through an intermediate relay server. 

I ran `tailscale ping sdrive-node1` from the cellular terminal:

```text
pong from sdrive-node1 (100.64.0.10) via 157.48.x.x:41641 in 28ms (direct)
pong from sdrive-node1 (100.64.0.10) via 157.48.x.x:41641 in 27ms (direct)
```

The output confirmed that Tailscale’s STUN (Session Traversal Utilities for NAT) discovery successfully negotiated direct UDP hole-punching on port 41641. The traffic was traveling over a **100% direct, end-to-end encrypted peer-to-peer WireGuard tunnel** straight through my home ISP’s CGNAT pool.

### 4. Benchmarking Encrypted Mesh Throughput (`iperf3`)
Next, I needed to quantify the cryptographic performance penalty of running WireGuard on the Rockchip RK3566’s quad-core Cortex-A55 processor.

I ran `iperf3 -s` on the board and ran a 4-stream TCP throughput benchmark over the `tailscale0` IP address (`100.64.0.10`):

```text
[ ID] Interval           Transfer     Bitrate         Retr
[SUM]   0.00-30.00  sec  1.61 GBytes   462 Mbits/sec    0             sender
[SUM]   0.00-30.00  sec  1.61 GBytes   461 Mbits/sec                  receiver
```

The results were outstanding:
- **Encrypted Throughput:** **462 Mbps** sustained.
- **Resource Footprint:** The `tailscaled` daemon consumed only **28.4 MB of RAM**.
- **CPU Utilization:** Overall system CPU load averaged only **20.7%** during active encryption, with the core handling kernel `softirq` interrupts peaking at 64%.
- **Thermal Impact:** SoC temperature rose by only $5.4^\circ\text{C}$ (to 41.8°C).

At 462 Mbps (roughly 58 MB/s), the encrypted tunnel can transfer a typical 10MB raw mobile photo in less than **180 milliseconds**. The software-driven ChaCha20-Poly1305 encryption on the RK3566 is more than fast enough to saturate any standard residential home broadband upload connection.

I documented the full latency matrix and performance telemetry in `benchmarks/week-01-mesh-throughput.md`.

Finally, I drafted our formal Tailscale Access Control List policy at `config/tailscale/tailscale-acl.json.example`, restricting family mobile devices strictly to port 3900 (Garage S3) and port 8080 (museum API) while locking administrative SSH access strictly to authorized admin machines.

## What confused me

The primary area of technical friction today was understanding **MTU clamping** on WireGuard interfaces. 

Standard Ethernet interfaces use an MTU of 1500 bytes. Because WireGuard encapsulates packets in UDP datagrams, it adds up to 80 bytes of cryptographic and protocol overhead. Tailscale sets the virtual `tailscale0` MTU to **1280 bytes** (the minimum guaranteed IPv6 packet size). 

I wanted to ensure that large multi-megabyte photo uploads wouldn't stall due to Path MTU Discovery (PMTUD) blackholes on mobile networks. I tested packet traversal using `ping -M do -s 1252 100.64.0.10` (1252 bytes payload + 28 bytes ICMP/IP header = 1280 bytes), verifying that packets pass cleanly without fragmentation and that the Linux kernel automatically handles TCP MSS clamping to 1240 bytes.

## Tomorrow

Tomorrow is Day 12: **The Soak Test and Power-Pull Validation**. We will set up continuous background telemetry logging, perform our first deliberate power-pull test to verify filesystem journal integrity across ungraceful power cuts, and finalize all benchmarks in preparation for the Week 01 Retrospective.
