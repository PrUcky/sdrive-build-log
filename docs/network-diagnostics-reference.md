# sdrive — Network Diagnostics Quick Reference

A field-tested cheatsheet of every network diagnostic command used during Week 02 bring-up on the Radxa ROCK 3C. Each command is documented with its exact flags, what it reveals, and when to reach for it.

---

## 1. Socket Inspection: `ss`

The modern replacement for `netstat`. Queries the kernel's netlink socket interface directly.

```bash
# Show all listening TCP and UDP sockets with process info (no DNS lookups)
ss -tulnp

# Show established connections only
ss -tnp state established

# Show sockets on a specific port
ss -tlnp sport = :8080

# Show TCP socket memory usage (send/receive buffer sizes)
ss -tm

# Count connections by state
ss -s
```

**When to use:** After deploying any new service, verify it is listening on the correct interface and port. Run `ss -tulnp` obsessively. If a service binds to `0.0.0.0` when it should bind to `127.0.0.1`, you have an exposure.

---

## 2. Packet Capture: `tcpdump`

The definitive packet sniffer. Captures raw frames from a network interface.

```bash
# Capture TCP traffic on a specific port (no DNS resolution for speed)
tcpdump -i eth0 -n tcp port 8000

# Capture and display packet contents in ASCII
tcpdump -i eth0 -n -A tcp port 8080

# Capture to file for later analysis (e.g., in Wireshark)
tcpdump -i eth0 -n -w /tmp/capture.pcap tcp port 3900

# Capture only SYN packets (new connections)
tcpdump -i eth0 -n 'tcp[tcpflags] & tcp-syn != 0'

# Capture DNS queries
tcpdump -i eth0 -n udp port 53
```

**When to use:** When traffic is reaching the machine but the application isn't responding correctly. Proves whether packets arrive, whether the TCP handshake completes, and whether the application sends a response.

---

## 3. DNS Resolution: `dig`

The authoritative DNS diagnostic tool. Shows raw wire-format responses including TTLs, authority records, and response flags.

```bash
# Standard A record lookup
dig ente.io

# Query a specific resolver
dig @1.1.1.1 ente.io

# Short output (just the answer)
dig +short ente.io

# Show query time only
dig ente.io +stats | grep "Query time"

# Trace the full recursive resolution path
dig +trace ente.io

# Reverse DNS lookup
dig -x 192.168.1.150

# Query for MX records
dig ente.io MX

# Query for AAAA (IPv6) records
dig ente.io AAAA
```

**When to use:** When hostnames don't resolve, when resolution is slow, when you suspect DNS caching or poisoning, or when you need to compare answers across different resolvers.

---

## 4. Path Visualization: `traceroute`

 Maps the hop-by-hop path from this machine to a destination by sending packets with incrementing TTL values.

```bash
# Standard traceroute (no DNS resolution for speed)
traceroute -n 1.1.1.1

# TCP traceroute on a specific port (bypasses ICMP-blocking firewalls)
traceroute -T -p 443 1.1.1.1

# UDP traceroute (default protocol)
traceroute -U -n 8.8.8.8

# Set max hops
traceroute -n -m 15 1.1.1.1
```

**When to use:** When connectivity works but latency is unexpectedly high. Identifies which hop introduces the delay. Also confirms CGNAT topology (look for `100.64.x.x` at hop 2).

---

## 5. HTTP Transaction Tracing: `curl -v`

Verbose curl shows the complete lifecycle of an HTTP request: DNS lookup, TCP connect, TLS negotiation, request/response headers, and body.

```bash
# Full verbose HTTP request
curl -v http://192.168.1.150:8080/health

# HTTPS with TLS handshake details
curl -v https://api.ente.io/health

# Show only response headers
curl -I http://192.168.1.150:3900

# POST with JSON body
curl -v -X POST -H "Content-Type: application/json" -d '{"key":"value"}' http://localhost:8080/api

# Follow redirects verbosely
curl -vL http://192.168.1.150:8080/

# Time the connection phases
curl -w "dns: %{time_namelookup}s\nconnect: %{time_connect}s\ntls: %{time_appconnect}s\ntotal: %{time_total}s\n" -o /dev/null -s http://192.168.1.150:8080/
```

**Output prefix guide:**
- `*` — curl internal state narration
- `>` — request headers sent to server
- `<` — response headers received from server

**When to use:** Debugging HTTP 4xx/5xx errors, verifying CORS headers, checking TLS certificate validity, timing connection phases.

---

## 6. Interface & Route Management: `ip`

```bash
# Brief interface summary
ip -br addr show

# Show IPv4 addresses only
ip -4 addr show eth0

# Show IPv6 addresses only
ip -6 addr show eth0

# Show routing table
ip route show

# Show ARP/neighbor table
ip neigh show

# Delete default route (DANGER: breaks internet)
ip route del default

# Restore default route
ip route add default via 192.168.1.1 dev eth0

# Show link-layer details (MAC, MTU, state)
ip link show eth0
```

---

## 7. Firewall: `ufw`

```bash
# Show numbered rules
ufw status numbered

# Show verbose status (default policies)
ufw status verbose

# Allow from specific subnet
ufw allow from 192.168.1.0/24 to any port 8080 proto tcp comment 'museum API'

# Allow localhost only
ufw allow from 127.0.0.1 to any port 5432 proto tcp comment 'postgresql'

# Delete rule by number
ufw delete 3

# Reload after editing raw rules
ufw reload
```

---

## 8. DNS Resolver Status: `resolvectl`

```bash
# Show current resolver configuration
resolvectl status

# Flush DNS cache
resolvectl flush-caches

# Show cache statistics
resolvectl statistics

# Resolve a specific name (bypasses /etc/hosts)
resolvectl query ente.io
```

---

## 9. Connectivity Quick Checks

```bash
# Gateway reachability
ping -c 3 192.168.1.1

# Internet reachability (bypasses DNS)
ping -c 3 1.1.1.1

# DNS + internet reachability
ping -c 3 cloudflare.com

# Tailscale overlay reachability
ping -c 3 100.64.0.10
```

---

*Reference compiled during Week 02 of the sdrive build log. All commands tested on Armbian (Debian 12 Bookworm) running on Radxa ROCK 3C (RK3566).*
