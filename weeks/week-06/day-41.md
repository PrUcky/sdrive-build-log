# Day 41: Four Layers of Paranoia — The End-to-End Security Review

*October 7, 2026*

With Caddy deployed, tuned, and locked behind the host firewall, the infrastructure is conceptually complete. Today I took a step back to audit the entire system from a security perspective. I wrote `docs/security-architecture.md` to document the findings. 

When you build a system piecemeal — OS one week, network the next, containers the next — you sometimes lose the forest for the trees. Looking at the final stack today, it's remarkably hostile to attackers.

## The Threat Model

Most home servers fail because they implicitly trust the local network, or they punch a hole through the router (port 80/443) and pray that their reverse proxy never has a CVE. 

I assume my ISP is snooping, my local WiFi is untrusted, and that zero-day exploits exist for every piece of software I run.

## Layer 1: The Invisibility Cloak

Tailscale + UFW. Because of the `sdrive-firewall.sh` script I wrote on Day 39, the appliance drops all packets originating from the physical LAN interface unless they are destined for port 22 (SSH). It drops everything else.

To the public internet, the board is behind CGNAT and doesn't exist.
To the local network, it's a black box.
To the Tailnet, it's an authenticated API. 

## Layer 2: The TLS Envelope

If you have a valid Tailscale identity and can reach the virtual interface, you still hit Caddy first. Caddy enforces TLS 1.3. It prevents downgraded encryption attacks. It strips out fingerprinting headers. And because it's written in Go, it is completely immune to the buffer overflow attacks that plague older proxies written in C.

## Layer 3: The Zero-Trust API

If you break through Caddy, you hit Museum. Museum requires a JWT token for every API call. The token is generated via the Secure Remote Password (SRP) protocol. Museum doesn't trust Caddy, and Caddy doesn't trust Museum. They just pass bytes. 

## Layer 4: The Math

If you bypass Tailscale, exploit a zero-day in Caddy, bypass the JWT authentication in Museum, and manage to dump the entire PostgreSQL database and the 400 GB of Garage blob data... you have nothing.

Every photo is encrypted on the phone with XChaCha20-Poly1305 before it ever hits the network. The keys to decrypt those photos are themselves encrypted by the user's master key. The server never sees the master key. 

You can steal the ROCK 3C. You can steal the SSD. You can wiretap the Tailnet. The cryptography holds.

## Prepping for Gate B

Gate B is October 25: *Complete one-app upload/retrieval proof.* 

The backend is ready. The network is ready. The security is ready. The infrastructure work is essentially finished. 

For the next two weeks, the focus shifts. I need to make sure the automated maintenance scripts (watchdogs, backups, log rotation) run silently and reliably. I need to coordinate with my teammate who is building the UI/UX rebranding for the client app. 

The heavy lifting is done. Now, we wait and watch the telemetry.
