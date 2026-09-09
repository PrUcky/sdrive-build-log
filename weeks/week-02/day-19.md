# Day 19: Week 02 Retrospective — The Network Is Not an Abstraction Anymore

*September 9, 2026*

Last day of Week 02. The ROCK 3C has been running for ten days straight. I've spent six of those days doing nothing but networking — mapping subnets, capturing packets, poisoning DNS, crushing MTUs, deleting routes, tracing hops, reading firewall logs, and writing diagnostic scripts. Today is the retrospective: assessing what was built, what was learned, and what gaps remain before Week 03 drops containers onto this foundation.

I started the morning by re-reading the roadmap's exit criteria for Week 02:

> *"Given an address, a port and a URL, narrate every step from typing it to seeing a response — and when it fails, reach for the right tool instead of guessing."*

Yesterday's end-to-end packet walk — eight annotated steps from DNS resolution through TCP teardown — was the proof. I can narrate every hop now. More importantly, I know which tool to reach for at each layer: `dig` for DNS, `ip route` for routing, `ip neigh` for ARP, `tcpdump` for the wire, `curl -v` for HTTP, `ufw status` for firewalling, `ss` for sockets, `journalctl` for logs. The exit criteria is met.

But meeting the exit criteria isn't the same as being ready. While writing the formal retrospective and the weekly article today, I catalogued several things that went better than expected and several that still make me nervous.

**What went well:**
- The deliberate breakage methodology. Every tool was learned not by reading about it but by breaking something and then diagnosing the breakage. The MTU crush on Day 14 was terrifying in the moment — watching SSH lock up completely — but the watchdog recovered exactly as designed. That moment of genuine fear taught me more about TCP retransmission than any tutorial ever could.
- The DNS poisoning demo on Day 15. Seeing `dig @192.168.1.100 ente.io +short` return my own desktop's IP was a visceral demonstration of why DNS security matters. It converted an abstract threat into a concrete, reproducible attack.
- The Golden Signals framework. Mapping Google's SRE observability model to our tiny appliance on Day 17 gave me a mental framework that will scale to any system. Latency, traffic, errors, saturation — four numbers, infinite diagnostic power.

**What still concerns me:**
- Docker's DNS resolution. I discovered on Day 18 that `systemd-resolved` listens on `127.0.0.53`, which Docker containers can't see by default. I need to solve this before Week 03's `docker compose up` or name resolution inside containers will fail silently.
- IPv6 readiness. We hardened the firewall preemptively, but the board has never actually been tested with a global IPv6 prefix. If the ISP enables prefix delegation, we'll need to verify the firewall holds under real IPv6 traffic.
- The single point of failure in the SD card. All this networking infrastructure is meaningless if the boot medium dies. Week 04's storage work needs to seriously address this.

I spent the rest of the day writing the Week 02 formal retrospective (`weeks/week-02/retro.md`) and the public technical article. The article traces the journey from "the board is on the network" to "I understand every packet that crosses the wire" — covering the TCP handshake anatomy, the DNS trust chain, the CGNAT topology, and the Golden Signals observability framework.

The containers are next. Week 03 is where the actual application stack comes alive — PostgreSQL, Garage, `museum`, all running in Docker containers on this hardened network foundation. Everything we've built in the last two weeks exists to serve that moment.

Ten days of uptime. Zero kernel errors. Zero security incidents. Zero unplanned reboots. The foundation is solid.
