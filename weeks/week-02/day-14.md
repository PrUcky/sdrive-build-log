# Day 14: Subnets, TCP Handshakes, and Intentional Sabotage

*September 4, 2026*

The ROCK 3C has been running continuously for nearly 96 hours since the power-pull resilience tests of Week 01. Touching the fluted edges of the passive aluminum heatsink, it feels warm—right around that 48°C equilibrium we established. Today marks the beginning of Week 02. The focus shifts entirely to networking. Before we start deploying heavy storage engines or container orchestration, I need to know exactly how this board behaves on the wire. We are moving beyond theoretical architecture into raw packet-level reality.

I started the morning by mapping the local subnet. It’s a foundational step, but critical for ensuring our edge appliance isn't colliding with DHCP ranges or competing for bandwidth with noisy IoT devices. 

```bash
root@sdrive:~# ip -4 addr show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 192.168.1.150/24 brd 192.168.1.255 scope global eth0
```

The router gave us `192.168.1.150` based on the MAC address binding I set up earlier. I ran a quick `nmap -sn 192.168.1.0/24` from my Windows desktop just to survey the LAN. The scan returned the ISP gateway at `.1`, a few dormant smart TVs, my desktop at `.100`, and our silent, monolithic node at `.150`. The airspace is clear. 

Before deploying Garage or PostgreSQL, I wanted to prove Layer 7 connectivity in its purest form. No frameworks, no load balancers. Just raw TCP sockets. I spun up Python’s built-in HTTP server, binding it to port 8000.

```bash
root@sdrive:~# python3 -m http.server 8000 --bind 0.0.0.0
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
```

I could have just loaded `http://192.168.1.150:8000` in my browser and called it a success, but that misses the point of this phase. I want to see the mechanics. I opened a second SSH session and fired up `tcpdump`, filtering strictly for our HTTP port, dropping name resolution to keep the output blazing fast.

```bash
root@sdrive:~# tcpdump -i eth0 -n tcp port 8000
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
```

I hit refresh on the browser. The terminal exploded with traffic. Seeing it happen in real-time never gets old. The classic TCP three-way handshake unfolded perfectly over the RTL8211F Gigabit Ethernet PHY:

```
10:14:22.105234 IP 192.168.1.100.54321 > 192.168.1.150.8000: Flags [S], seq 3491823101, win 64240, options [mss 1460,nop,wscale 8,nop,nop,sackOK], length 0
10:14:22.105312 IP 192.168.1.150.8000 > 192.168.1.100.54321: Flags [S.], seq 1123456789, ack 3491823102, win 65160, options [mss 1460,sackOK,TS val 123456 ecr 0,nop,wscale 7], length 0
10:14:22.106124 IP 192.168.1.100.54321 > 192.168.1.150.8000: Flags [.], ack 1, win 252, length 0
```

SYN from the desktop. SYN-ACK from the board. ACK back. The sequence numbers aligned, the window scaled, and the connection was established. The microscopic voltage fluctuations on the twisted pair copper were translating perfectly into ordered network frames. It’s a beautiful, fragile system.

Which is exactly why it was time to break it.

During Week 01, we wrote `scripts/simulate-network-breakage.sh`. It was a theoretical tool then; today, it became our chaos engineering lab. I wanted to see how the system reacts when the network degrades—not just failing completely, but entering a "zombie" state where the link is up but traffic is severely choked. This simulates the exact kind of nasty cellular handoff or hotel Wi-Fi captive portal interference the appliance will eventually face in production overlay networks.

I executed the script, targeting the MTU (Maximum Transmission Unit).

```bash
root@sdrive:~# ./scripts/simulate-network-breakage.sh mtu-drop
[WARNING] Dropping eth0 MTU from 1500 to 500 bytes.
[WARNING] Network degradation simulation active.
```

Instantly, things felt wrong. I tried to `scp` a dummy 10MB file from my desktop to the board. The progress bar crawled to 4%, stuttered, and froze entirely. 

Over on the `tcpdump` terminal, the output was a bloodbath of TCP Retransmissions and Fragment Reassembly Timeouts. The TCP sliding window collapsed entirely as the two operating systems desperately tried to negotiate payload sizes that the artificially crippled interface could no longer handle. Packets were being fragmented, dropped, and resent in an endless, agonizing loop. 

My primary SSH session locked up completely. The cursor stopped blinking. 

This is the moment of panic in any remote server deployment. The board is physically on my desk, but I forced myself to treat it like it was locked in a server rack three thousand miles away. I couldn't pull the power. I couldn't plug in a keyboard. I had to wait and trust the self-healing architecture we laid down in Week 01.

I sat back and watched the amber activity LED on the ethernet port. It was blinking erratically, struggling to push out retransmissions. 

One minute passed. The `sdrive-network-watchdog.service` should be executing its health check right about now, pinging the gateway. With the MTU crushed, the ICMP replies might be getting through, or they might be timing out. I held my breath.

Two minutes passed. The SSH terminal was still dead. Had I bricked the network stack? Did the watchdog fail to recognize the degradation?

At exactly two minutes and forty-five seconds, the amber LED on the ROCK 3C went completely dark. A second later, it flashed back to life, solid amber, then rhythmic green.

My frozen SSH terminal suddenly spat out a `client_loop: send disconnect: Broken pipe` and dropped me back to my local prompt. 

The watchdog had worked. It detected the persistent latency and gateway instability, realized the interface was in a degraded state, and ruthlessly cycled the `eth0` link, clearing the artificial MTU limitation and reloading the standard `sysctl` network buffers. 

I hit the up arrow and re-SSH'd into the board.

```bash
Last login: Fri Sep 4 10:12:33 2026 from 192.168.1.100
root@sdrive:~# ip link show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
```

MTU was back to 1500. The network was stable. The board had healed itself.

Today was a revelation. We don't just trust the network anymore; we expect it to be a hostile environment. We expect packets to drop, routing to fail, and latency to spike. By verifying that our TCP stack behaves predictably and that our watchdog daemons can aggressively recover a lost interface without human intervention, we’ve proven that the foundational layer is rock solid. 

Tomorrow, we take this bulletproof network layer and start carving it up with network namespaces and isolated containers. The real stack is about to take shape.