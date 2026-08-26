# sdrive — Architectural Diagrams

This directory contains formal, version-controlled architecture diagrams for the `sdrive` personal cloud appliance, rendered in [Mermaid.js](https://mermaid.js.org/) format.

---

## 1. System Architecture (`system-architecture.mermaid`)
Visualizes the physical and logical boundaries of the system, illustrating the client-side cryptographic engine, the WireGuard network transport layer, and the strict decoupling between the Go metadata control plane and the Rust object storage data plane on the Radxa ROCK 3C appliance.

## 2. Ingestion Sequence (`ingestion-sequence.mermaid`)
A four-stage sequence diagram detailing the complete lifecycle of a photo upload:
1. Client-side EXIF extraction, thumbnail generation, and `Argon2id` + `XChaCha20-Poly1305` authenticated encryption.
2. Out-of-band upload authorization and HMAC-SHA256 pre-signed S3 PUT URL issuance by `museum`.
3. Direct ciphertext payload streaming into `Garage` over Tailscale (bypassing the application server heap).
4. Two-phase metadata commitment to PostgreSQL 16.

## 3. Network Topology (`network-topology.mermaid`)
Illustrates how `sdrive` punches through Carrier-Grade NAT (CGNAT) and home firewalls without port forwarding using Tailscale's STUN/ICE NAT traversal and WireGuard peer-to-peer mesh overlays.
