# Packets Don't Lie: What Six Days of Deliberate Network Sabotage Taught Me About Building Reliable Infrastructure

*By Pratyush Chaudhary · September 9, 2026 · 16 min read*

---

## 1. The Premise: Learning Networking by Breaking Everything

There is a specific flavor of confidence that comes from watching your own infrastructure fail, understanding exactly why it failed, and knowing exactly how to fix it. That confidence cannot be learned from diagrams, blog posts, or YouTube tutorials. It can only be earned by deliberately sabotaging a live system and then diagnosing the damage with nothing but a terminal and the right diagnostic tools.

This article documents six days of systematic network exploration on a Radxa ROCK 3C single-board computer — the hardware foundation of the **sdrive** home photo-backup appliance. The board runs Armbian Linux, has a single Realtek RTL8211F Gigabit Ethernet PHY, and sits behind Carrier-Grade NAT on a residential internet connection. Over the course of a week, I mapped the local subnet, captured raw TCP handshakes, poisoned my own DNS, crushed the MTU to 500 bytes, deleted the default route, traced every hop to Cloudflare's edge, and built a complete observability framework — all on a $35 single-board computer that draws less power than a phone charger.

The goal was not to build a network. The goal was to understand one well enough to debug it without guessing.

---

## 2. The TCP Three-Way Handshake: Seeing the Invisible

The first experiment was the most fundamental. I wanted to see a TCP connection form in real time — not in a textbook diagram, but in actual packet captures on the wire.

I started a minimal HTTP server on the ROCK 3C:

```bash
python3 -m http.server 8000 --bind 0.0.0.0
```

Then opened `tcpdump` on a second SSH session, filtering for port 8000 with no DNS resolution (the `-n` flag is critical for speed — without it, `tcpdump` tries to reverse-resolve every IP address, which can delay output by seconds):

```bash
tcpdump -i eth0 -n tcp port 8000
```

When I loaded the page from my desktop browser, three packets appeared in rapid succession:

```
10:14:22.105234 IP 192.168.1.100.54321 > 192.168.1.150.8000: Flags [S]
10:14:22.105312 IP 192.168.1.150.8000 > 192.168.1.100.54321: Flags [S.]
10:14:22.106124 IP 192.168.1.100.54321 > 192.168.1.150.8000: Flags [.]
```

SYN. SYN-ACK. ACK. The entire handshake completed in 0.89 milliseconds. The flag notation is terse but unambiguous: `[S]` is a SYN, `[S.]` is a SYN-ACK (the `.` represents the ACK flag), and `[.]` is a bare ACK.

What struck me was the precision. The ROCK 3C's kernel responded to the SYN in 78 microseconds — that's the time for the packet to traverse the RTL8211F PHY, pass through the kernel's network stack, check the firewall rules, find a matching listening socket, and generate the SYN-ACK. Seventy-eight microseconds. On a $35 board. The Cortex-A55 cores may be modest by desktop standards, but for network I/O at the edge, they are more than sufficient.

---

## 3. DNS: The Layer That Lies to You

DNS is the first thing that happens when you type a URL, and it is the single most fragile link in the chain. On a residential internet connection behind Carrier-Grade NAT, the default DNS resolver is the home router, which proxies queries to the ISP's recursive resolver. This creates a chain of trust that is exactly three links long — and any one of those links can lie.

I benchmarked DNS latency across three resolvers from the ROCK 3C:

| Resolver | Provider | Latency |
|---|---|---|
| `1.1.1.1` | Cloudflare | 8 ms |
| `8.8.8.8` | Google | 12 ms |
| `192.168.1.1` | Local Router | 14 ms |

Cloudflare's anycast was the fastest because their Points of Presence are physically distributed closer to ISP edges than Google's infrastructure in our region. The local router was the slowest because it adds a hop — it receives our query, forwards it to the ISP's resolver, waits for the response, and passes it back.

But latency is the least interesting property of DNS. The interesting property is **trustworthiness**. To demonstrate this, I spun up a local `dnsmasq` instance on my desktop configured to return `192.168.1.100` for every query:

```bash
dig @192.168.1.100 ente.io +short
192.168.1.100
```

The board now believed that Ente's production API server lived at my desktop. If the `museum` backend were running, it would attempt to authenticate against my Windows machine. The authentication would fail, but the connection attempt itself reveals the appliance's identity and network position.

This is not a theoretical attack. ISP resolvers have been caught intercepting NXDOMAIN responses and redirecting them to advertising pages. Hotel Wi-Fi captive portals routinely hijack DNS to force authentication. Cellular networks often inject transparent DNS proxies that cache aggressively and serve stale records.

The solution is defense in depth:

```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8 192.168.1.1
FallbackDNS=1.0.0.1 8.8.4.4
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
```

Three independent resolvers from three different organizations. DNS-over-TLS encrypts the queries when the upstream supports it. DNSSEC validates that the answers haven't been tampered with (in `allow-downgrade` mode, because hard-failing on DNSSEC errors would lock us off the internet entirely when the ISP strips signatures).

---

## 4. The CGNAT Discovery: Why Port Forwarding Is Impossible

One of the most important discoveries of the week came from a simple `traceroute`:

```
 1  192.168.1.1      0.85 ms    ← Home router
 2  100.64.0.1       4.15 ms    ← ISP CGNAT gateway
 3  * * *                       ← Silent backbone
 4  172.16.48.1      8.37 ms    ← ISP peering edge
 5  72.14.209.1      9.03 ms    ← Google peering router
 6  1.1.1.1          8.15 ms    ← Cloudflare anycast
```

Hop 2 — `100.64.0.1` — is an address in the RFC 6598 Shared Address Space (`100.64.0.0/10`), the range specifically reserved for Carrier-Grade NAT infrastructure. This confirms that our home network does not have a dedicated public IPv4 address. Our router's "WAN IP" is itself a private address inside the ISP's NAT pool.

This has a profound architectural implication: **port forwarding is mathematically impossible**. Even if we opened port 443 on our home router, the ISP's CGNAT would never route inbound connections to our specific NAT session. The board is unreachable from the public internet by design — not by our design, but by the ISP's infrastructure.

This is precisely why the sdrive architecture relies on Tailscale's WireGuard mesh overlay. Tailscale uses STUN and ICE protocols to establish direct peer-to-peer UDP tunnels that punch through both the home router's NAT and the ISP's CGNAT. The key insight is that WireGuard uses UDP, and UDP NAT traversal succeeds where TCP NAT traversal fails because UDP's connectionless nature allows both peers to send packets simultaneously, creating matching NAT mapping entries on both sides.

---

## 5. The MTU Crush: When the Network Goes Zombie

The most dramatic experiment was the deliberate MTU reduction. MTU (Maximum Transmission Unit) is the largest packet size an interface will send without fragmenting. Ethernet's default MTU is 1500 bytes. I dropped it to 500:

```bash
./scripts/simulate-network-breakage.sh mtu-drop
```

The effect was immediate and devastating. SSH froze. File transfers died at 4%. The `tcpdump` output showed a cascade of TCP retransmissions as both operating systems desperately tried to negotiate payload sizes that the crippled interface could no longer handle. The TCP sliding window collapsed, packets fragmented, fragments were dropped, and the retransmission timer entered exponential backoff.

But the board didn't die. After approximately 165 seconds, the `sdrive-network-watchdog` systemd service detected the persistent gateway instability, cycled the `eth0` interface, and the standard MTU was restored automatically. The watchdog had worked exactly as designed.

This failure mode — where the link is technically up but traffic is severely degraded — is the most insidious kind of network problem. A complete link failure is easy to detect and easy to recover from. A zombie link, where packets occasionally get through but most are dropped or corrupted, can persist for hours before anyone notices. The MTU crush simulates exactly the kind of path MTU mismatch that occurs when VPN tunnels add encapsulation overhead without adjusting the inner MTU — a problem we will encounter in Week 06 when the WireGuard overlay is deployed.

---

## 6. The Four Golden Signals: An Observability Framework for a $35 Computer

Google's Site Reliability Engineering book defines four fundamental metrics — the "Golden Signals" — that capture the health of any service:

1. **Latency** — How long does it take to serve a request?
2. **Traffic** — How many requests are we handling?
3. **Errors** — What fraction of requests fail?
4. **Saturation** — How close are we to resource exhaustion?

I mapped these to the sdrive appliance and built a diagnostic script that outputs all four in a single screen:

```
========================================
 sdrive — Golden Signals Snapshot
 2026-09-07 11:02:14 IST
========================================

[LATENCY] DNS resolution to Cloudflare:
;; Query time: 7 msec

[TRAFFIC] Network counters (eth0):
  RX: 807 MB  TX: 40 MB

[ERRORS] Interface error counters:
    RX errors: 0  dropped: 0  overruns: 0  frame: 0
    TX errors: 0  dropped: 0  carrier: 0  collisions: 0

[SATURATION] Resource utilization:
  Memory: 142 MB / 3788 MB (3%)
  Disk:   13G / 58G (23%)
  Load:   0.08 0.03 0.01
  Uptime: up 8 days, 14 hours, 22 minutes
  CPU:    47°C
========================================
```

The entire diagnostic runs in under two seconds. No Grafana. No Prometheus. No cloud dashboards. Just `bash`, `dig`, `ip`, `free`, `df`, and `journalctl`. This is observability at the edge — where the infrastructure budget is zero and the diagnostic budget is a single SSH session.

The key insight is that these four signals are sufficient. When something goes wrong in Week 03, 04, or 05, the first question is always one of these four: Is it slow? Is it overloaded? Is it returning errors? Is it running out of resources? Every other metric — CPU temperature, disk IOPS, network throughput, container restart counts — is implementation detail that feeds into one of these four categories.

---

## 7. The Firewall: Deny by Default, Allow by Exception

The ROCK 3C's firewall policy follows a single principle: **everything is denied unless explicitly permitted, scoped to the minimum network surface required**.

```
Default: DENY incoming, ALLOW outgoing, DENY routed

Rule 1: 22/tcp    from 192.168.1.0/24    (SSH — key auth only)
Rule 2: 8080/tcp  from 192.168.1.0/24    (museum API — Week 03)
Rule 3: 3900/tcp  from 192.168.1.0/24    (Garage S3 — Week 03)
Rule 4: 5432/tcp  from 127.0.0.1         (PostgreSQL — localhost only)
```

Notice that PostgreSQL is bound exclusively to `127.0.0.1`. Not the LAN. Not the overlay. Localhost. The database has no business accepting connections from any network interface. The Go backend connects over the loopback adapter, and that is the only path. This is the principle of least privilege applied at the network layer.

IPv6 is handled separately: all inbound IPv6 traffic is dropped except ICMPv6 Neighbour Discovery, which the kernel requires for link-layer address resolution. The board currently has only a link-local `fe80::` address, but if the ISP enables global prefix delegation tomorrow, the firewall will silently drop all inbound traffic before it reaches userspace.

---

## 8. What Changes When Containers Arrive

Week 03 introduces Docker containers — and containers change everything about networking.

The most critical discovery from this week was that `systemd-resolved` uses a stub listener on `127.0.0.53`. Docker containers run in their own network namespace and cannot see the host's loopback address. This means that unless we explicitly configure Docker's DNS, container processes will fail to resolve hostnames — and the failure will be silent, mysterious, and time-consuming to diagnose.

The fix is straightforward: configure the Docker daemon to use our hardened resolver chain directly:

```json
{
  "dns": ["1.1.1.1", "8.8.8.8", "192.168.1.1"]
}
```

But knowing the fix isn't the point. The point is that we discovered the problem before it bit us, because writing documentation forced us to think clearly about every layer of the stack. The DNS stub resolver issue would have cost an entire day of debugging in Week 03 if it had surfaced as a mysterious "container can't reach the internet" failure.

---

## 9. The Routing Table: Two Lines That Control Everything

The kernel routing table on the ROCK 3C contains exactly two entries:

```
default via 192.168.1.1 dev eth0
192.168.1.0/24 dev eth0
```

The first line says: "for anything not on our subnet, send it to the gateway." The second says: "for anything on our subnet, deliver it directly." That's it. Two lines. The entire data plane for the machine.

When Tailscale is deployed in Week 06, a third line will appear:

```
100.64.0.0/10 dev tailscale0
```

This is how the WireGuard overlay coexists with the physical LAN. The kernel checks each destination address against the routing table, and the most specific matching prefix wins. Traffic to `100.64.0.10` matches the `/10` Tailscale route and goes through the encrypted tunnel. Traffic to `192.168.1.100` matches the `/24` LAN route and goes straight to the wire. The kernel doesn't care that one interface is a physical Realtek PHY and the other is a virtual userspace construct. To the routing table, they're both just entries.

I verified this by deliberately deleting the default route:

```bash
ip route del default
ping 1.1.1.1     # → "Network is unreachable" (instant, clean failure)
ping 192.168.1.1  # → success (LAN route still works)
```

The internet disappeared. The LAN kept working. The failure was immediate and unambiguous — infinitely better than the mysterious timeouts that would occur if the route were misconfigured rather than missing.

---

## 10. The Week in Numbers

| Metric | Value |
|---|---|
| Days of focused networking work | 6 |
| Diagnostic tools mastered | 9 (`tcpdump`, `dig`, `ss`, `traceroute`, `curl -v`, `ip`, `ufw`, `journalctl`, `resolvectl`) |
| Deliberate breakage experiments | 5 (MTU crush, route deletion, DNS poisoning, firewall block, NXDOMAIN) |
| Listening sockets (attack surface) | 3 |
| Network interface errors (10-day window) | 0 |
| Kernel errors (10-day window) | 0 |
| Board uptime at end of week | 10 days |
| Total artifacts produced | 8 files (configs, scripts, docs, benchmarks) |

---

The network is not an abstraction anymore. It's a system I understand well enough to break on purpose and fix with confidence. Every packet that crosses the ROCK 3C's Realtek PHY is observable, filterable, and explainable. Every firewall rule is documented and justified. Every DNS query is encrypted when possible and validated when the upstream supports it.

Next week, containers land on this foundation. PostgreSQL, Garage, and Ente's `museum` backend will come alive inside Docker's isolated network namespaces. The networking knowledge from this week isn't background reading for that work — it is the prerequisite. Without understanding TCP, DNS, routing, and firewalling at the packet level, debugging container networking would be an exercise in blind guessing.

Packets don't lie. They just need someone who knows how to read them.

---

*This article is part of the **`sdrive` Build Log** — a 12-week public engineering series documenting the ground-up development of an end-to-end encrypted home photo backup appliance. Track the daily code commits and logs on GitHub: [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
