# Day 16: Dual-Stack, Socket Tables, and Tracing Every Hop to the Edge

*September 6, 2026*

Saturday morning. The house is quiet and the ROCK 3C's power LED is a steady pinprick of white light on the desk, barely visible through the passive heatsink fins. I touched the aluminum out of habit — 46°C, cooler than usual. Ambient temperature dropped overnight. The thermal equilibrium shifts with the seasons; something to account for when we eventually deploy this in a closet with no airflow.

Today I'm finishing the networking toolkit. After two days of DNS, firewalls, and routing tables, there are three critical diagnostic tools I haven't touched yet: `ss` for socket-level inspection, `curl -v` for HTTP transaction tracing, and `traceroute` for path visualization. And I need to confront the elephant in the room: IPv6. Our ISP provides it. The board sees it. And if I don't understand how dual-stack routing works, it will bite me the moment Tailscale starts injecting overlay routes.

I started with `ss` — the modern replacement for `netstat`. Where `netstat` was chatty and slow (it parsed `/proc/net/tcp` line by line), `ss` talks directly to the kernel's netlink socket interface and returns structured data in microseconds. It's the difference between reading a book about a building and looking at the building's blueprints.

```bash
root@sdrive:~# ss -tulnp
Netid  State   Recv-Q  Send-Q    Local Address:Port     Peer Address:Port  Process
tcp    LISTEN  0       128       0.0.0.0:22              0.0.0.0:*          users:(("sshd",pid=842,fd=3))
tcp    LISTEN  0       128       [::]:22                 [::]:*             users:(("sshd",pid=842,fd=4))
udp    UNCONN  0       0         127.0.0.53%lo:53        0.0.0.0:*          users:(("systemd-resolve",pid=614,fd=13))
```

Three listening sockets. That's the entire attack surface of this machine right now. SSH on port 22, bound to both IPv4 (`0.0.0.0`) and IPv6 (`[::]`), and `systemd-resolved` on port 53, bound exclusively to the loopback adapter. Nothing else. No web server, no database, no storage daemon. The board is as minimal as it can possibly be while still being remotely administrable.

The `-t` flag filters TCP, `-u` filters UDP, `-l` shows only listeners, `-n` prevents DNS lookups on addresses (which would be ironic given yesterday's DNS deep-dive), and `-p` shows the process behind each socket. I will run this command obsessively every time we bring up a new service in Week 03 to verify that nothing is listening on an interface it shouldn't be.

But notice something crucial: SSH is listening on `[::]` — the IPv6 wildcard. That means if this board has a globally routable IPv6 address, SSH is reachable from the entire internet, bypassing our router's NAT entirely. IPv4 NAT is not a security feature, but it is a de facto shield. IPv6 removes that shield completely.

```bash
root@sdrive:~# ip -6 addr show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet6 fe80::c615:a3ff:fe91:7d42/64 scope link
       valid_lft forever preferred_lft forever
```

Only a link-local address (`fe80::`). No global unicast prefix. Our ISP either isn't providing IPv6 prefix delegation to this subnet, or the router isn't forwarding Router Advertisement packets. For now, this is actually fine — it means the board is invisible on the IPv6 internet, and our dual-stack posture is effectively IPv4-only. But I need to plan for the day when our ISP flips the switch and suddenly the board gets a globally routable `2xxx:` prefix.

I hardened the IPv6 posture preemptively:

```bash
root@sdrive:~# cat >> /etc/ufw/before6.rules << 'MARKER'
# sdrive: drop all inbound IPv6 except ICMPv6 neighbor/router discovery
-A ufw6-before-input -p icmpv6 --icmpv6-type neighbour-solicitation -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type neighbour-advertisement -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type router-advertisement -j ACCEPT
MARKER
root@sdrive:~# ufw reload
```

This ensures that even if a global IPv6 prefix appears tomorrow, the firewall will silently drop all inbound IPv6 traffic except the bare minimum required for neighbor discovery (which the kernel needs to function on the local link). SSH over IPv6 from the internet? Blocked. Port scans on our hypothetical global address? Dropped at the kernel netfilter before they even reach userspace.

Next: `traceroute`. I wanted to see the actual path packets take from this board to the infrastructure we'll eventually depend on.

```bash
root@sdrive:~# traceroute -n 1.1.1.1
traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 60 byte packets
 1  192.168.1.1  0.912 ms  0.834 ms  0.793 ms
 2  100.64.0.1   4.231 ms  4.118 ms  4.092 ms
 3  * * *
 4  172.16.48.1  8.412 ms  8.391 ms  8.304 ms
 5  72.14.209.1  9.102 ms  8.983 ms  9.014 ms
 6  1.1.1.1      8.234 ms  8.121 ms  8.089 ms
```

Six hops. The first is our home router. The second — `100.64.0.1` — is the ISP's CGNAT gateway. That `100.64.x.x` address is RFC 6598 Shared Address Space, the range specifically reserved for carrier-grade NAT infrastructure. This confirms what we suspected: our home network is behind CGNAT, meaning no amount of port forwarding on our router will make this board reachable from the public internet. This is precisely why Tailscale exists in our architecture.

Hop 3 is a silent node — it doesn't respond to TTL-exceeded ICMP messages, which is common in ISP backbone routers configured to deprioritize ICMP. Hop 4 is the ISP's peering edge. Hop 5 is a Google peering router (the `72.14.209.x` prefix belongs to Google's edge network), and hop 6 is Cloudflare's `1.1.1.1` anycast endpoint. Six hops, 8 milliseconds. Clean.

I ran the same trace to Google's DNS:

```bash
root@sdrive:~# traceroute -n 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  192.168.1.1  0.898 ms  0.821 ms  0.784 ms
 2  100.64.0.1   4.312 ms  4.208 ms  4.145 ms
 3  * * *
 4  172.16.48.1  8.523 ms  8.467 ms  8.401 ms
 5  72.14.209.1  9.234 ms  9.112 ms  9.089 ms
 6  8.8.8.8      12.412 ms  12.334 ms  12.287 ms
```

Four extra milliseconds to reach Google compared to Cloudflare, which validates yesterday's `dig` latency measurements. The first five hops are identical — same ISP path — but the final hop diverges at the peering exchange. Cloudflare's anycast is physically closer to our ISP's edge than Google's. This is useful operational intelligence for choosing DNS resolver priority.

Now for the tool I've been saving: `curl -v`. Verbose curl is the Swiss Army knife of HTTP debugging. It shows you the entire lifecycle of an HTTP transaction — DNS lookup, TCP connect, TLS handshake (if applicable), request headers sent, response headers received, and body transferred. I fired up Python's HTTP server again on port 8000 and hit it from the board itself:

```bash
root@sdrive:~# python3 -m http.server 8000 --bind 0.0.0.0 &
root@sdrive:~# curl -v http://127.0.0.1:8000/
*   Trying 127.0.0.1:8000...
* Connected to 127.0.0.1 (127.0.0.1) port 8000
> GET / HTTP/1.1
> Host: 127.0.0.1:8000
> User-Agent: curl/7.88.1
> Accept: */*
>
* HTTP 1.0, assume close after body
< HTTP/1.0 200 OK
< Server: SimpleHTTP/0.6 Python/3.11.2
< Date: Sat, 06 Sep 2026 15:24:18 GMT
< Content-type: text/html; charset=utf-8
< Content-Length: 912
<
<!DOCTYPE HTML>
... (directory listing) ...
* Closing connection 0
```

Every line prefixed with `*` is curl's internal state narration. Lines with `>` are request headers we sent. Lines with `<` are response headers we received. The sequence tells a story: curl resolved the address (trivially, since it's `127.0.0.1`), opened a TCP connection, sent an HTTP/1.1 GET request, received an HTTP/1.0 200 response (Python's SimpleHTTP server is ancient and defaults to HTTP/1.0), read the body, and closed the connection.

This output format will become critical in Week 03 when we're debugging why the `museum` API server returns a `401 Unauthorized` or why Garage's S3 endpoint responds with `NoSuchBucket`. The headers tell you everything — the status code, the content type, the server identity, whether keep-alive is active, whether CORS headers are present. Reading `curl -v` output fluently is a prerequisite for debugging any HTTP-based system.

I killed the background Python server and ran one final connectivity audit — a comprehensive snapshot of every network-relevant state on this machine:

```bash
root@sdrive:~# echo "=== Interfaces ===" && ip -br addr show
=== Interfaces ===
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             192.168.1.150/24 fe80::c615:a3ff:fe91:7d42/64

root@sdrive:~# echo "=== Routes ===" && ip route show
=== Routes ===
default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.150 metric 100
192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.150 metric 100

root@sdrive:~# echo "=== DNS ===" && resolvectl status --no-pager | head -6
=== DNS ===
Global
       Protocols: +LLMNR +mDNS +DNSOverTLS DNSSEC=allow-downgrade
resolv.conf mode: stub
         DNS Servers: 1.1.1.1 8.8.8.8 192.168.1.1
Fallback DNS Servers: 1.0.0.1 8.8.4.4

root@sdrive:~# echo "=== Firewall ===" && ufw status numbered
=== Firewall ===
     [1] 22/tcp                     ALLOW IN    192.168.1.0/24
     [2] 8080/tcp                   ALLOW IN    192.168.1.0/24
     [3] 3900/tcp                   ALLOW IN    192.168.1.0/24
     [4] 5432/tcp                   ALLOW IN    127.0.0.1

root@sdrive:~# echo "=== Listeners ===" && ss -tulnp
=== Listeners ===
Netid  State   Recv-Q  Send-Q    Local Address:Port     Peer Address:Port  Process
tcp    LISTEN  0       128       0.0.0.0:22              0.0.0.0:*          users:(("sshd",pid=842,fd=3))
tcp    LISTEN  0       128       [::]:22                 [::]:*             users:(("sshd",pid=842,fd=4))
udp    UNCONN  0       0         127.0.0.53%lo:53        0.0.0.0:*          users:(("systemd-resolve",pid=614,fd=13))
```

Two interfaces. Two routes. Three DNS resolvers with TLS encryption. Four firewall rules. Three listening sockets. That's the complete network identity of this machine. I can recite it from memory now. More importantly, when something breaks — and it will — I have a known-good baseline snapshot to diff against.

Three days into Week 02 and the networking toolkit is complete. I can inspect sockets with `ss`, trace packets with `tcpdump`, resolve names with `dig`, visualize paths with `traceroute`, debug HTTP transactions with `curl -v`, and manipulate routes and firewall rules with `ip` and `ufw`. Every tool has been used not just to observe, but to deliberately break something and then diagnose the breakage.

The roadmap says Week 02's exit criteria is: "given an address, a port and a URL, narrate every step from typing it to seeing a response — and when it fails, reach for the right tool instead of guessing." After today, I can do exactly that. The network is no longer a black box. It's a system I understand well enough to break on purpose and fix with confidence.

Tomorrow we shift from diagnostics to documentation: capturing the complete network architecture, writing the Week 02 reference docs, and preparing the ground for Week 03's container stack.
