# Day 05 — The Why

**Week:** 00 · **Date:** 2026-08-23 · **Hours:** ~5.0

Today was an unexpectedly therapeutic engineering exercise. I spent the entire day without opening a code editor, compiling a binary, or touching a terminal command. Instead, I dedicated nearly five hours to writing pure markdown documents inside `docs/decisions/`. Forcing myself to formally defend every technical compromise before the physical board boots is the single most valuable discipline in systems engineering.

## What I actually did

I authored the five core Architecture Decision Records (ADRs) that establish the immutable constraints of the `sdrive` project. In commercial software engineering, ADRs are often treated as tedious bureaucratic compliance checkboxes. But when building an embedded hardware appliance solo, writing formal ADRs acts as an essential cognitive mirror—it forces you to interrogate your own unspoken assumptions and separates genuine technical requirements from emotional hype.

Here is the breakdown of the five decision records committed today:

1. **`0001-ente-over-immich.md` (Zero-Knowledge Privacy vs. Server-Side AI):**
   The immediate default choice in the modern self-hosted community is Immich. Immich is a masterpiece of open-source software—it has a gorgeous mobile UI, massive community momentum, and powerful server-side machine learning for facial recognition, object detection, and natural language search. However, Immich operates under a traditional trusted-server model: the server holds full plaintext access to every image, video, and EXIF coordinate. If an adversary physically steals the `sdrive` appliance from my house, a simple forensic dump of the storage drive yields all family photos in the clear. Ente solves this at the cryptographic foundation by pushing all encryption, thumbnail generation, and ML indexing to the handset. The server only ever stores opaque ciphertext blobs. We deliberately trade server-side search convenience for mathematical privacy.

2. **`0002-rock-3c-over-rk3576.md` (Right-Sizing Compute to Cryptographic Reality):**
   The single-board computer market is currently saturated with next-generation Rockchip RK3576 and RK3588 boards featuring massive 6 TOPS Neural Processing Units (NPUs), 8-core Big.LITTLE CPU topologies, and high-bandwidth LPDDR5 RAM. Because we chose Ente in ADR 0001, our server performs zero neural inference, zero video transcoding, and zero image decoding. Running an RK3576 board would mean paying double the bill-of-materials (BOM) cost and dissipating 10 to 15 watts of heat just to let an expensive NPU sit permanently at 0% utilization. The older, highly efficient RK3566 SoC on the Radxa ROCK 3C draws under 2.5 watts at idle, runs comfortably cool in a fanless 3D-printed enclosure, and provides more than enough I/O bandwidth to saturate a Gigabit network interface.

3. **`0003-tailscale-before-headscale.md` (Pragmatic Velocity vs. Ideological Purity):**
   A personal cloud backup appliance is worthless if it only functions when connected to the living room Wi-Fi. Overcoming Carrier-Grade NAT (CGNAT) requires a WireGuard mesh overlay. While our ultimate long-term goal is running a 100% self-hosted coordination server via **Headscale**, attempting to bring up Headscale, configure DERP relay nodes, and manage custom control planes during Week 01 would create massive cognitive friction. We adopt Tailscale’s managed SaaS coordination layer for weeks 0 through 5 to guarantee instantaneous, battle-tested remote connectivity. This preserves development momentum while keeping the network layer completely decoupled so we can execute a seamless cutover to self-hosted Headscale during Week 06 and Week 12.

4. **`0004-garage-over-minio.md` (Lightweight Edge Storage vs. Enterprise Datacenter Bloat):**
   This is the pivotal architectural record of the entire stack. Because Ente utilizes pre-signed URLs, the mobile client streams multi-megabyte encrypted blobs directly into the S3 endpoint. The object storage daemon is not a quiet, internal database; it is a heavily hit, client-facing service. MinIO is designed for enterprise data centers with multi-node clusters and gigabytes of spare RAM. Running MinIO on a 4GB single-board computer with flash storage frequently causes memory bloat, GC pressure, and aggressive disk I/O warnings. **Garage**, engineered in Rust by Deuxfleurs, was designed from the ground up for low-power edge nodes. It runs as a lightweight static binary, uses less than 60MB of RAM, and handles slow consumer flash storage with total stability.

5. **`0005-sd-boot-for-prototype.md` (Rapid Prototyping vs. Production Flash Durability):**
   While eMMC modules provide superior longevity and NVMe drives offer blazing I/O throughput, dealing with flashing eMMC modules and configuring bootloader PCIe drivers on Day 1 introduces unnecessary hardware friction. The prototype (v1) will boot and run entirely from a high-endurance SanDisk microSD card to allow rapid OS re-flashing. The production revision (v2) will formalize the separation of concerns: the Linux OS and PostgreSQL metadata database will migrate to an onboard eMMC module for write durability, while the high-volume Garage ciphertext blobs will reside on a dedicated NVMe SSD in the underside M.2 slot.

Writing these ADRs revealed an incredible architectural truth: the entire system architecture is a cascading domino effect driven by a single core requirement. The moment we committed to zero-knowledge end-to-end encryption in ADR 0001, every downstream hardware and software decision fell into place with mathematical inevitability.

## What confused me

The biggest technical challenge while drafting ADR 0004 was thoroughly mapping out the network load characteristics of pre-signed URLs. In a standard web architecture, developers assume that the application server shields the database and storage engine from external traffic. But with pre-signed URLs, the mobile client establishes a direct TCP socket with the S3 daemon (port 3900 on Garage) over the Tailscale VPN interface. 

This means that if a user backs up 500 photos after a vacation, the storage daemon must handle hundreds of concurrent HTTP PUT connections without leaking file descriptors or choking on memory buffers. Understanding that Garage's asynchronous Rust runtime (built on Tokio) handles high-concurrency I/O with negligible memory overhead was the final deciding factor that sealed the decision to abandon MinIO entirely.

## Tomorrow

Tomorrow is Day 06: Prove You Understand It. I will step away from documentation, draw the entire architectural topology from memory on a physical whiteboard twice, author `docs/architecture.md` and `docs/glossary.md`, and unbox the physical hardware components as they arrive.
