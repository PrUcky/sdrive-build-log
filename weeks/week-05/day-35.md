# Day 35: Assembling the Gate A Evidence — The Network Proof Is Complete

*October 1, 2026*

Three days before Gate A. The evidence is all there — scattered across Days 32, 33, and 34. Today I assembled it into a single document, ran the final verification, and thought about what the gate actually proves.

## The Final Verification Run

Before writing the evidence package, I ran the complete test sequence one more time to confirm nothing has regressed:

```bash
# 1. Tailscale daemon running
root@sdrive:~# systemctl is-active tailscaled
active

# 2. All containers healthy
root@sdrive:~# docker compose ps --format '{{.Name}}: {{.Status}}'
sdrive-stack-postgres-1: Up 72 hours (healthy)
sdrive-stack-garage-1: Up 72 hours (healthy)
sdrive-stack-museum-1: Up 72 hours (healthy)

# 3. Tailscale peers connected
root@sdrive:~# tailscale status
100.100.42.17   sdrive          linux   -
100.100.89.3    desktop-pc      windows idle
100.100.64.11   pixel-phone     android active; direct 10.45.72.18:41641

# 4. Museum reachable through tunnel
root@sdrive:~# curl -s http://100.100.42.17:8080/health
{"status":"ok"}

# 5. Tailscale health check
root@sdrive:~# ./scripts/sdrive-tailscale-health.sh
[OK] tailscaled daemon: running (PID 4821)
[OK] Backend state: Running
[OK] Self: sdrive (100.100.42.17)
[OK] Peers: 2 device(s) on tailnet
[OK] IPv4: yes, IPv6: no
[OK] Preferred DERP: 11 (Bangalore)
[OK] NAT mapping: consistent (direct connections likely)
[OK] Interface tailscale0: state=UNKNOWN, mtu=1280
[OK] tailscaled memory: 26 MB
=== Exit code: 0 ===

# 6. Full system health
root@sdrive:~# ./scripts/sdrive-golden-signals.sh
[LATENCY] Health endpoint response time:
  museum /health: 14ms
[TRAFFIC] ...
[ERRORS] Container restart count: 0
[SATURATION]
  Memory: 382 MB / 3788 MB (10%)
  Disk:   5.5G / 458G (1%)
  Load:   0.09 0.07 0.04
  CPU:    48°C
```

Everything green. Zero restart counts. Three days of uptime without intervention. The appliance is stable.

I then ran the demo scenario from the phone on mobile data:

1. Opened Ente app, pointed at `http://100.100.42.17:8080`
2. Took a fresh photo with the camera
3. Watched it upload through the Tailscale tunnel (2 seconds)
4. Opened the gallery on a second device (also on Tailscale)
5. Saw the photo appear in the gallery
6. Tapped it — full resolution loaded in 1.3 seconds
7. Downloaded it — identical to the original

The complete round trip works. Phone A photographs → encrypts → uploads through WireGuard tunnel → Museum stores metadata in PostgreSQL → Garage stores encrypted blob on SSD → Phone B requests through its own tunnel → decrypts → displays. End-to-end encryption maintained throughout. Zero plaintext touches the server.

## What Gate A Actually Proves

Gate A isn't about Tailscale. Tailscale is the tool. The gate is about proving that the **embedded network architecture works**: a phone can back up photos to a home appliance from anywhere in the world, without exposing a single port to the public internet.

This matters because it eliminates the three biggest barriers to self-hosted photo backup:

1. **CGNAT** — most ISPs now use CGNAT, making port forwarding impossible. Tailscale's hole-punching bypasses this entirely.

2. **Dynamic DNS** — home IP addresses change. Tailscale IPs don't. `100.100.42.17` is the same address whether the ISP rotates the WAN IP or the router reboots.

3. **Security** — traditional port forwarding exposes services to the entire internet. With Tailscale, the attack surface is a single UDP port that cryptographically ignores unauthorized peers. It's invisible to port scanners.

The architecture is:
- **Managed Tailscale coordination** (key exchange, peer discovery)
- **Embedded WireGuard** (kernel-level encryption, direct peer-to-peer when possible)
- **Encrypted DERP relay** (fallback when direct connection fails)
- **One installed app** (Ente, which handles both the photo backup and the server communication)
- **Android VPN consent** (required for Tailscale on the phone, one-time setup)

This matches the roadmap specification exactly.

## The Evidence Document

I wrote `docs/gate-a-evidence.md` as the formal gate evidence package. It contains:

- 11 criteria, all passed, with references to the daily log entries that contain the proof
- Architecture diagram showing the phone-to-appliance data path
- Throughput table across all three connection paths (LAN, mobile, DERP)
- Security posture assessment (zero public ports, zero port forwarding)
- Resource impact delta (before/after Tailscale)
- All failure modes tested with recovery times
- Verification commands for reproducing each test

This document is what I'll present on October 4. It's evidence-based, not aspirational. Every number in the document comes from a terminal session logged in a daily entry.

## Remaining Week 05 Work

Gate A is ready, but Week 05 isn't done. The remaining days before the retro:

- **Day 36:** MagicDNS configuration and HTTPS endpoint planning (Caddy prep for Week 06)
- **Day 37:** Week 05 retrospective and weekly article

The gate evidence is assembled. The tunnel is proven. The appliance backs up photos from anywhere. Now we polish and close the week.

Tomorrow: MagicDNS hostnames and the Caddy HTTPS roadmap for Week 06.
