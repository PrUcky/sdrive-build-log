# Day 34: Tunnel Throughput and the DERP Fallback — Every Path Tested

*September 30, 2026*

Four days until Gate A. The tunnel works — Day 33 proved that. But "works" isn't enough. I need to know how fast it works across every possible connection path, and I need to prove the fallback works when the fast path fails. Today I benchmarked the WireGuard tunnel throughput across three network conditions and deliberately forced DERP relay fallback to verify the worst-case scenario.

## Benchmark Design

Three connection scenarios, each tested with `iperf3` through the Tailscale tunnel and then with a real 50-photo upload batch:

1. **LAN direct** — phone on home WiFi, same LAN as the board
2. **Mobile direct** — phone on 4G LTE, hole-punched through dual CGNAT
3. **DERP relay** — direct path blocked, traffic relayed through Tailscale's DERP server

I installed `iperf3` on the ROCK 3C and ran it in server mode:

```bash
root@sdrive:~# apt install -y iperf3
root@sdrive:~# iperf3 -s -B 100.100.42.17
```

Binding to the Tailscale IP ensures the test traffic goes through the WireGuard tunnel, not the raw LAN interface.

## Test 1: LAN Direct (WiFi, Same Network)

```bash
# Phone (Termux via Tailscale VPN):
$ iperf3 -c 100.100.42.17 -t 30
Connecting to host 100.100.42.17, port 5201
[ ID] Interval       Transfer    Bitrate
[  5]  0.00-30.00 sec  1.34 GBytes  383 Mbits/sec  sender
[  5]  0.00-30.00 sec  1.34 GBytes  382 Mbits/sec  receiver
```

382 Mbps through the WireGuard tunnel on the same LAN. That's 91% of the raw WiFi 5 throughput (the phone's WiFi adapter maxes out around 420 Mbps). The 9% overhead is the WireGuard encryption (ChaCha20-Poly1305) and packet encapsulation (60 bytes per packet). On the ROCK 3C, the kernel's WireGuard module handles the crypto entirely in kernel space — no userspace copies, no context switches.

I then ran a 50-photo batch upload through the Ente app:

```
LAN Direct Batch Upload:
  Photos: 50 (182 MB total)
  Duration: 29 seconds
  Throughput: 6.3 MB/s (50.2 Mbps)
  Latency: 3 ms (tailscale ping)
```

The upload throughput (6.3 MB/s) is lower than the raw tunnel bandwidth (47.7 MB/s) because of Museum's sequential S3 PUT serialization — the same Garage SQLite WAL bottleneck from Day 28. The tunnel isn't the limiting factor on LAN. The application is.

## Test 2: Mobile Direct (4G LTE, Hole-Punched)

I disconnected from WiFi and verified the Tailscale path:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via 10.45.72.18:41641 in 46ms
```

Direct connection. 46 ms latency. Then the `iperf3` test:

```bash
# Phone (4G LTE via Tailscale):
$ iperf3 -c 100.100.42.17 -t 30
[  5]  0.00-30.00 sec   62.4 MBytes  17.5 Mbits/sec  sender
[  5]  0.00-30.00 sec   61.8 MBytes  17.3 Mbits/sec  receiver
```

17.3 Mbps — limited by the mobile uplink bandwidth, not the tunnel. The carrier's upload cap for my 4G plan is roughly 20 Mbps, so we're hitting 86% of the theoretical maximum through the encrypted tunnel. WireGuard's overhead is negligible compared to the mobile network's latency and bandwidth constraints.

The 50-photo batch:

```
Mobile Direct Batch Upload:
  Photos: 50 (182 MB total)
  Duration: 92 seconds
  Throughput: 2.0 MB/s (15.8 Mbps)
  Latency: 46 ms (tailscale ping)
```

92 seconds for 50 photos over mobile data. 2.0 MB/s effective throughput. The experience is noticeably slower than WiFi, but completely functional — this is background backup speed, running silently while the user goes about their day. Most people won't even notice it happening.

## Test 3: DERP Relay (Forced Fallback)

This is the critical test. When direct hole-punching fails — aggressive corporate firewalls, symmetric NAT, or UDP-blocking networks — Tailscale falls back to DERP relays. I needed to prove the backup path works.

I forced DERP relay by blocking the direct UDP path. On the ROCK 3C, I added a temporary UFW rule to drop UDP from the phone's carrier IP:

```bash
root@sdrive:~# ufw deny from 10.45.72.18
Rule added
```

This blocked the direct WireGuard path. Tailscale detected the connection failure within seconds and automatically switched to the DERP relay:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via DERP(blr) in 112ms
```

`via DERP(blr)` — traffic is now relaying through Tailscale's Bangalore DERP server. Latency jumped from 46 ms (direct) to 112 ms (relayed). The packet path is now:

```
Phone → carrier → internet → DERP(blr) → internet → ISP → router → ROCK 3C
```

Two extra internet hops, but the traffic is still end-to-end encrypted with WireGuard. The DERP server sees only encrypted WireGuard packets — it cannot inspect or modify the photo data.

The `iperf3` test through DERP:

```bash
$ iperf3 -c 100.100.42.17 -t 30
[  5]  0.00-30.00 sec   28.4 MBytes  7.94 Mbits/sec  sender
[  5]  0.00-30.00 sec   27.8 MBytes  7.78 Mbits/sec  receiver
```

7.78 Mbps through the DERP relay. That's 45% of the direct mobile throughput. The reduction comes from the additional hops and the DERP server's bandwidth management (it serves many Tailscale users, not just us). But 7.78 Mbps is still fast enough for background photo backup.

The 50-photo batch through DERP:

```
DERP Relay Batch Upload:
  Photos: 50 (182 MB total)
  Duration: 168 seconds
  Throughput: 1.1 MB/s (8.6 Mbits/sec)
  Latency: 112 ms (tailscale ping)
```

168 seconds — about 3 minutes for 50 photos. Slower, but functional. The photos uploaded correctly, decrypted correctly on the receiving device, and the gallery showed all of them. The DERP fallback works. It's the worst case, and the worst case is still good enough.

I removed the temporary firewall rule:

```bash
root@sdrive:~# ufw delete deny from 10.45.72.18
Rule deleted
```

Tailscale detected the direct path was available again and automatically switched back within 30 seconds:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via 10.45.72.18:41641 in 44ms
```

Automatic path recovery. No manual intervention. No restart required.

## The Throughput Map

All three paths in one table:

| Path | Tunnel Bandwidth | Photo Upload | Latency | When Used |
|---|---|---|---|---|
| LAN Direct | 382 Mbps | 6.3 MB/s (29s/50 photos) | 3 ms | Home WiFi |
| Mobile Direct | 17.3 Mbps | 2.0 MB/s (92s/50 photos) | 46 ms | Mobile data, most WiFi |
| DERP Relay | 7.8 Mbps | 1.1 MB/s (168s/50 photos) | 112 ms | Corporate/hotel, hard NAT |

The LAN path is bottlenecked by the application (Garage's SQLite WAL). The mobile path is bottlenecked by the carrier's uplink. The DERP path is bottlenecked by relay hop overhead. In no scenario is the WireGuard tunnel itself the bottleneck.

## Automatic Path Selection

I tested the transition between paths. Connected to WiFi (LAN direct, 3 ms). Disconnected WiFi (mobile direct, 46 ms). Reconnected WiFi (back to LAN direct, 3 ms). Each transition happened automatically within 5–15 seconds. The Ente app continued uploading through the transitions — it saw a brief pause (while Tailscale renegotiated the path) and then resumed. No errors. No failed uploads. No lost data.

This is the user experience we're building toward: you install the app, point it at the Tailscale IP, and it backs up your photos continuously regardless of which network you're on. Leave home, switch to mobile data, arrive at the office behind a corporate firewall, connect to hotel WiFi with a captive portal — the backup adapts automatically.

## Resource Impact During Tunnel Traffic

I monitored the ROCK 3C during the DERP relay test (the most CPU-intensive path):

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 394 MB / 3788 MB (10%)
  Disk:   5.5G / 458G (1%)
  Load:   0.67 0.42 0.28
  CPU:    52°C
```

Load 0.67 during sustained tunnel traffic. Temperature 52°C. Memory 394 MB. The kernel's WireGuard module is handling the crypto without breaking a sweat. Even the DERP relay path — the worst case — barely registers as load on the quad-core A55.

I checked the Tailscale daemon's memory:

```bash
root@sdrive:~# ps -o rss= -p $(pgrep tailscaled) | awk '{print $1/1024 " MB"}'n26.4 MB
```

26.4 MB. No significant growth from the idle baseline (24 MB). The Tailscale daemon handles control plane operations; the actual data-plane crypto is in the kernel.

## Gate A Evidence Checklist

With today's benchmarks, the Gate A evidence is nearly complete:

| Criterion | Status | Evidence |
|---|---|---|
| Tailscale installed and running | ✅ | Day 32: v1.72.1, systemd-managed |
| Direct tunnel through CGNAT | ✅ | Day 32: 44ms direct, hole-punched |
| Photo upload through tunnel (WiFi) | ✅ | Day 33: 0.5s per photo |
| Photo upload through tunnel (mobile) | ✅ | Day 33: 1.8s per photo |
| Photo download through tunnel | ✅ | Day 33: 1.2s full-res on mobile |
| Multi-device photo viewing | ✅ | Day 33: phone A uploads, phone B views |
| Account isolation via tunnel | ✅ | Day 33: separate accounts, zero cross-leak |
| Tunnel throughput benchmarked | ✅ | Day 34: 382/17.3/7.8 Mbps across 3 paths |
| DERP relay fallback proven | ✅ | Day 34: 112ms, 1.1 MB/s, photos intact |
| Automatic path recovery | ✅ | Day 34: WiFi → mobile → WiFi, seamless |
| Resource impact measured | ✅ | Day 34: +2 MB memory, load 0.67, 52°C |

All embedded network criteria are met. Gate A is ready.

Tomorrow: assembling the Gate A evidence package and documenting the network proof.
