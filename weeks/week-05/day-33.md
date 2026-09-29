# Day 33: The First Photo Through the Tunnel

*September 29, 2026*

Yesterday I proved the Tailscale tunnel works: `curl http://100.100.42.17:8080/health` returned `{"status":"ok"}` from mobile data. Today I proved the thing that actually matters: the Ente app on my phone can upload and download photos through the WireGuard tunnel while on mobile data, completely bypassing CGNAT, with no port forwarding, no public IP, and no exposed attack surface.

## Configuring the Ente App for the Tailscale Endpoint

The Ente app uses a server URL to know where to send API requests. Until now, it was configured to `http://192.168.1.150:8080` — the ROCK 3C's LAN IP. This only works when the phone is on the same WiFi network.

I changed the server URL in the app to the Tailscale IP:

```
Server: http://100.100.42.17:8080
```

This address works everywhere:
- On the home WiFi, Tailscale detects same-LAN and routes directly (~3 ms)
- On mobile data, Tailscale hole-punches through CGNAT (~45 ms)
- On hotel WiFi, Tailscale relays through DERP (~100 ms)

One URL. Every network. No reconfiguration needed.

## The Upload Test: WiFi First

I started on home WiFi to verify nothing broke. Opened the Ente app, pointed at `100.100.42.17:8080`, and uploaded a test photo:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via 192.168.1.42:41641 in 3ms
```

Direct connection over LAN. The photo uploaded in the same half-second as before. No perceptible difference from using the LAN IP directly. Tailscale adds negligible overhead when both peers are on the same network.

## The Upload Test: Mobile Data

I disconnected from WiFi, waited for the phone to connect via 4G LTE, verified the Tailscale VPN was active, and uploaded another photo:

```bash
root@sdrive:~# tailscale ping pixel-phone
pong from pixel-phone (100.100.64.11) via 10.45.72.18:41641 in 44ms
```

Direct connection through dual CGNAT. The photo took about 2 seconds to upload (4.2 MB × 8 bits / ~18 Mbps effective mobile uplink = ~1.9 seconds, plus the 44 ms round-trip for the S3 confirmation). The upload progress bar advanced smoothly. The green checkmark appeared. The photo was backed up.

I verified on the server side:

```bash
root@sdrive:~# docker logs sdrive-stack-museum-1 --tail 5 2>&1 | grep -i upload
2026-09-29 15:47:31 INFO  File upload completed: file_id=1087, size=4194344, source_ip=100.100.64.11, duration=1842ms
```

The source IP is `100.100.64.11` — the phone's Tailscale IP, not its carrier IP. The upload went through the WireGuard tunnel. Duration: 1.842 seconds. That includes the mobile network latency, the encryption/decryption overhead, and the S3 write to Garage.

## The Download Test: Mobile Data

I opened the gallery on the phone (still on mobile data) and scrolled through the thumbnails. They loaded in about 300 ms each — slightly slower than on WiFi (~200 ms) due to the mobile network latency. Tapping a photo loaded the full resolution in about 1.2 seconds (vs 0.4 seconds on WiFi). The experience is noticeably slower but completely usable.

The bottleneck is the mobile network, not the tunnel. WireGuard adds approximately 60 bytes of overhead per packet (the WireGuard header), which is less than 0.5% on a typical 1400-byte MTU. The crypto (ChaCha20-Poly1305) runs in the Linux kernel and adds microseconds of latency. All the perceived slowness is mobile network latency and bandwidth.

## Batch Upload Over Mobile Data

I selected 20 photos (approximately 72 MB) and hit "Back Up All" while still on mobile data:

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
# Before: 5,440 objects, 4,218 MB
# After:  5,540 objects, 4,290 MB
```

100 new objects (20 photos × 5), 72 MB of data. The upload took approximately 35 seconds over 4G LTE. Effective throughput: ~2.1 MB/s (16.5 Mbps) — limited by the mobile uplink, not the tunnel or the appliance.

During the upload, the ROCK 3C barely noticed:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 388 MB / 3788 MB (10%)
  Disk:   5.3G / 458G (1%)
  Load:   0.34 0.21 0.12
  CPU:    50°C
```

Load 0.34. Temperature 50°C. The appliance doesn't care whether photos arrive over Gigabit Ethernet or 4G LTE — it processes them the same way.

## Multi-Device Verification

The critical demo scenario: photos backed up on phone A can be viewed on phone B under the same account. I logged into the same account on a second device (also connected to the tailnet via mobile data), opened the gallery, and saw all 1,080+ photos, including the ones just uploaded from the first phone.

I tapped a photo that was uploaded from phone A on mobile data, and it loaded on phone B on mobile data. The round trip:

1. Phone A encrypted the photo and uploaded through the tunnel to the ROCK 3C
2. Garage stored it on the SSD
3. Phone B requested the photo through its own tunnel to the ROCK 3C
4. Garage served the encrypted blob through the tunnel
5. Phone B decrypted and displayed it

Two tunnels, one appliance, two CGNAT traversals, end-to-end encryption, and the photo looks identical. This is the core demo scenario working end-to-end.

## Account Isolation Re-Verification

I also verified that a different Tailscale-connected device logged into a different Ente account sees only its own photos — not the other account's. Zero cross-contamination. The tailnet provides network access, but Ente's zero-knowledge encryption provides data isolation. Even though both accounts' encrypted blobs sit on the same SSD in the same Garage bucket, neither can decrypt the other's data.

## Connection Path Monitoring

I ran the new Tailscale health check script:

```bash
root@sdrive:~# ./scripts/sdrive-tailscale-health.sh
=== sdrive Tailscale Health === 2026-09-29 16:22:14 IST ===
[OK] tailscaled daemon: running (PID 4821)
[OK] Backend state: Running
[OK] Self: sdrive (100.100.42.17)
[OK] Peers: 2 device(s) on tailnet

--- Peer Status ---
  ● 100.100.89.3    desktop-pc      windows  direct 192.168.1.88:41641
  ● 100.100.64.11   pixel-phone     android  direct 10.45.72.18:41641

[OK] IPv4: yes, IPv6: no
[OK] Preferred DERP: 11 (Bangalore)
[OK] NAT mapping: consistent (direct connections likely)
[OK] Interface tailscale0: state=UNKNOWN, mtu=1280
[OK] tailscaled memory: 26 MB
=== Exit code: 0 ===
```

Both peers are direct connections. The preferred DERP relay is in Bangalore (closest to our location), but it's only a fallback — not currently in use. NAT mapping is consistent, meaning the ISP's CGNAT allows hole-punching.

Gate A is October 4 — five days away. Today's test proved the embedded network path works for the demo: phone connects, photos upload over the tunnel, and they're viewable on another device through the tunnel. What remains is stress testing the tunnel path and documenting the Gate A evidence.

Tomorrow: tunnel throughput benchmarks and DERP relay fallback testing.
