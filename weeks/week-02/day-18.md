# Day 18: The Complete Network Map and the End-to-End Packet Walk

*September 8, 2026*

Monday evening. Nine days of continuous uptime on the ROCK 3C. I came home from work, opened my laptop, and realized that after four days of deep networking exploration, the knowledge is scattered across four daily logs, three reference docs, and a benchmark file. Today's job is synthesis. I need to take everything we've learned — every `tcpdump` capture, every `dig` query, every firewall rule, every routing table entry — and distill it into a single, authoritative network architecture document. And then I need to prove the Week 02 exit criteria by walking a packet from my phone to the storage daemon and narrating every single hop.

I started by updating the network topology diagram. The original from Week 00 was aspirational — it showed the architecture we planned to build. Now I need it to reflect what actually exists, validated by real measurements.

The existing diagram had the right structure but was missing the detail we've accumulated: the CGNAT hop, the DNS resolver chain, the firewall rules, the IPv6 posture. I rewrote it from scratch, incorporating every empirically verified fact from this week:

```
Physical Layer (verified Week 01-02):

  [Mobile Phone]                         [Desktop: 192.168.1.100]
       |                                        |
  (Cellular / Wi-Fi)                     (Cat5e Ethernet)
       |                                        |
  [ISP CGNAT: 100.64.0.1]              [TP-Link GbE Switch]
       |                                        |
  [ISP Backbone: 172.16.48.1]          [Home Router: 192.168.1.1]
       |                                        |
  [Peering: 72.14.209.1]                       |
       |                               [Cat5e Ethernet]
  [Public Internet]                             |
                                    +-----------+-----------+
                                    |    ROCK 3C Appliance   |
                                    |                        |
                                    |  eth0: 192.168.1.150   |
                                    |  fe80::c615:a3ff:...   |
                                    |  MTU: 1500             |
                                    |                        |
                                    |  tailscale0: (Week 06) |
                                    |  100.64.0.10           |
                                    +-----------+------------+
                                                |
                                    +-----------+------------+
                                    |   Kernel Routing Table  |
                                    |                         |
                                    |  default via .1 eth0    |
                                    |  192.168.1.0/24 eth0    |
                                    |  (100.64.0.0/10 ts0)   |
                                    +-------------------------+
```

But the real deliverable of today isn't a diagram. It's the **end-to-end packet walk**. The roadmap says the Week 02 exit criteria is: "given an address, a port and a URL, narrate every step from typing it to seeing a response — and when it fails, reach for the right tool instead of guessing."

So here it is. A complete, annotated narration of what happens when a client on my desktop opens `http://192.168.1.150:8080/health` — the exact URL that the `museum` API will serve starting in Week 03.

I fired up the Python HTTP server one last time as a stand-in for `museum`, bound to port 8080:

```bash
root@sdrive:~# python3 -m http.server 8080 --bind 0.0.0.0 &
[1] 6241
```

Then I walked through every layer, from the application down to the wire and back up again, with a tool at every step to prove each assertion.

### Step 1: DNS Resolution (or lack thereof)

The URL uses a raw IP address (`192.168.1.150`), so the client's DNS resolver is never consulted. If the URL were `http://sdrive.local:8080/health`, the resolver would first check `/etc/hosts`, then query `systemd-resolved` at `127.0.0.53`, which would attempt mDNS on the local link. Since we're using a raw IP, we skip straight to TCP.

**Verification tool:** `dig` (not needed here, but would be the first tool if resolution failed).

### Step 2: Routing Decision

My desktop's kernel examines the destination IP `192.168.1.150` and consults its routing table. The address falls within the `192.168.1.0/24` subnet, which matches the directly-connected LAN route. No gateway is needed — the packet will be delivered directly on the local segment.

**Verification tool:** `ip route get 192.168.1.150`

```bash
# From desktop:
C:\> route print | findstr 192.168.1
192.168.1.0    255.255.255.0    On-link    192.168.1.100    281
```

### Step 3: ARP Resolution

The desktop knows it needs to deliver the frame directly to `192.168.1.150`, but Ethernet doesn't speak IP — it speaks MAC addresses. The kernel checks its ARP cache for the MAC address corresponding to `192.168.1.150`. If it's not cached, it broadcasts an ARP request: "who has 192.168.1.150? Tell 192.168.1.100."

The ROCK 3C's RTL8211F PHY responds with its MAC address. The desktop caches this mapping.

**Verification tool:** `ip neigh show` (Linux) or `arp -a` (Windows)

```bash
root@sdrive:~# ip neigh show | grep 192.168.1.100
192.168.1.100 dev eth0 lladdr 4c:ed:fb:XX:XX:XX REACHABLE
```

### Step 4: TCP Three-Way Handshake

The desktop's TCP stack allocates an ephemeral source port (e.g., 54321) and sends a SYN packet to `192.168.1.150:8080`. The ROCK 3C's kernel receives it, checks that port 8080 is open in UFW (rule #2: allowed from `192.168.1.0/24`), and passes it to the listening Python process. The SYN-ACK returns. The desktop ACKs. Connection established.

**Verification tool:** `tcpdump -i eth0 -n tcp port 8080`

```
20:14:22.105234 IP 192.168.1.100.54321 > 192.168.1.150.8080: Flags [S], seq 3491823101, win 64240
20:14:22.105312 IP 192.168.1.150.8080 > 192.168.1.100.54321: Flags [S.], seq 1123456789, ack 3491823102
20:14:22.106124 IP 192.168.1.100.54321 > 192.168.1.150.8080: Flags [.], ack 1, win 252
```

Total handshake time: 0.89 milliseconds. Verified against the Week 02 baseline.

### Step 5: HTTP Request

With the TCP connection established, the desktop sends the HTTP GET request:

```
GET /health HTTP/1.1
Host: 192.168.1.150:8080
User-Agent: curl/8.7.1
Accept: */*
```

The request travels inside a TCP segment, inside an IPv4 packet, inside an Ethernet frame. Three layers of encapsulation. The total overhead is 14 bytes (Ethernet) + 20 bytes (IP) + 20 bytes (TCP) + the HTTP payload. For a simple GET request, the overhead is roughly 50% of the total frame.

**Verification tool:** `curl -v http://192.168.1.150:8080/health`

### Step 6: Firewall Traversal

The incoming SYN packet hits the kernel's netfilter before reaching the application. UFW rule #2 allows TCP port 8080 from `192.168.1.0/24`. The source address `192.168.1.100` matches the subnet. The packet passes. If the request came from `10.0.0.50` (a different subnet), it would be silently dropped and logged to the journal as `UFW BLOCK`.

**Verification tool:** `ufw status numbered` + `journalctl -k --grep="UFW BLOCK"`

### Step 7: HTTP Response

The Python server processes the request and returns:

```
HTTP/1.0 200 OK
Server: SimpleHTTP/0.6 Python/3.11.2
Date: Mon, 08 Sep 2026 14:44:18 GMT
Content-type: text/html; charset=utf-8
Content-Length: 912
```

The response travels back through the same path in reverse: application → TCP segment → IP packet → Ethernet frame → Cat5e copper → switch → desktop NIC → desktop TCP stack → browser.

### Step 8: TCP Teardown

After the response is delivered, the server sends a FIN. The desktop ACKs. The desktop sends its own FIN. The server ACKs. The connection is cleanly torn down. The ephemeral port is released back to the kernel's port pool.

**Verification tool:** `ss -tn state time-wait`

---

That's it. Eight steps. DNS → routing → ARP → TCP handshake → HTTP request → firewall → HTTP response → TCP teardown. Every step observable, every step verifiable, every step breakable in a controlled way.

I spent the second half of the evening collecting all of this into a formal architecture document that will serve as the reference for every networking decision we make from this point forward. The document covers the physical topology, the IP addressing scheme, the DNS resolver chain, the firewall policy, the routing table structure, and the known performance baseline. It cross-references every daily log that contributed data.

The most important part of writing the architecture doc wasn't the content — it was the process of discovering what I didn't know I didn't know. While writing the ARP section, I realized I'd never verified the ARP cache timeout on Armbian. While writing the firewall section, I caught myself assuming UFW logs go to syslog (they go to the kernel ring buffer, accessible via `journalctl -k`). While documenting the DNS resolver chain, I noticed that `systemd-resolved` uses a stub listener on `127.0.0.53` rather than directly populating `/etc/resolv.conf` — a subtlety that will matter when Docker containers try to resolve hostnames in Week 03 because containers don't see the host's stub resolver by default.

That last discovery is the kind of bug that would have cost me an entire day of debugging in Week 03 if I hadn't caught it now. The whole point of documentation isn't to write things down for posterity. It's to force yourself to think clearly enough that the gaps in your understanding become visible before they become failures.

Tomorrow is the last day of Week 02. Retro time. We'll assess the exit criteria, write the Week 02 retrospective, and publish the weekly article. The containers are next.
