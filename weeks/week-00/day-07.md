# Day 07 — The Retrospective and The Essay

**Week:** 00 · **Date:** 2026-08-26 · **Hours:** ~6.0

Today marks the end of Week 00. The roadmap deliberately built Day 7 as a dedicated buffer day for retrospectives, synthesis, and long-form writing rather than cramming more raw development into the queue. Taking an entire afternoon to reflect on what was built over the last six days—and more importantly, what was understood—turned out to be the most demanding intellectual exercise of the entire orientation phase.

## What I actually did

I divided today’s six-hour block into two major engineering tasks: completing the formal Week 00 retrospective (`weeks/week-00/retro.md`) and authoring the first long-form technical article for public release (`content/articles/week-00-why-the-server-never-decrypts.md`).

I started with the retrospective. Reviewing the daily logs from Day 01 through Day 06 gave me a startling perspective on how much my understanding of this system evolved in just one week. On Day 01, I viewed `sdrive` through a generic, naive lens: essentially "a Raspberry Pi clone running an open-source photo server attached to an SSD." By Day 06, that simplistic model had been completely dismantled and replaced by a rigorous, zero-knowledge distributed systems architecture. 

In `retro.md`, I codified the four major milestones completed this week:
1. **The Cryptographic Foundation:** Validated the mathematical boundaries of client-side encryption (`Argon2id` key derivation, `XChaCha20-Poly1305` authenticated ciphers) where the server is an untrusted, zero-knowledge storage node.
2. **The Decision Records:** Authored and committed five immutable ADRs (`docs/decisions/0001` through `0005`), resolving the critical tradeoffs for Ente over Immich, ROCK 3C over RK3576, Tailscale before Headscale, Garage over MinIO, and SD-card bootstrapping.
3. **Repository & Administrative Security:** Established pre-commit secret scanning via `.gitleaks.toml`, bound the codebase to the GNU AGPL-3.0 copyleft license, and generated our dedicated Ed25519 administrative keypair with 100 bcrypt KDF rounds.
4. **Physical Hardware Inventory:** Unboxed and inspected the Radxa ROCK 3C, verified the power delivery rail specifications (5V/3A regulated DC), and applied the passive aluminum heatsink to the RK3566 SoC.

The second half of the day was dedicated to writing our first comprehensive technical essay: *"Why the Server Never Decrypts: Building a Zero-Knowledge Personal Cloud on a $35 Single Board Computer."* 

Writing this article forced me to translate technical decisions into a clear, compelling narrative. I walked through why traditional self-hosted solutions like Immich and Nextcloud, while brilliant, maintain a trusted-server security model that leaves personal data exposed to physical device theft. I broke down the out-of-band pre-signed URL ingestion loop, explaining why separating the metadata control plane (Go + PostgreSQL) from the high-throughput object storage plane (Rust + Garage) allows a ₹6,000 ARM board drawing 2.5 watts at idle to outperform traditional monolithic servers in both security and operational stability.

I also formally verified the **Week 0 Exit Criterion** defined in the master roadmap: *"You wrote 0004-garage-over-minio.md unaided. If you couldn't, spend another day here."* Having spent hours detailing Garage’s Tokio-based asynchronous I/O engine, low 50MB RAM footprint, and tolerance for consumer flash latency versus MinIO’s memory-heavy multi-node enterprise assumptions, I can defend that decision down to the kernel syscall level without looking at notes.

## What confused me

The biggest struggle today was editorial: finding the exact balance between technical precision and readable storytelling for the public article. When explaining cryptographic primitives and network ingestion loops, it is deceptively easy to slip into either dry, academic jargon or hand-wavy marketing fluff. 

For instance, explaining why `museum` issues an HMAC-SHA256 authenticated pre-signed URL to let the mobile client stream directly into Garage via HTTP PUT required three rewrites. The first version read like an RFC specification; the second version was too simplistic. I eventually settled on a concrete walkthrough contrasting the "monolithic proxy funnel" with the "out-of-band parking pass" model, complete with concrete memory overhead calculations showing why a monolithic proxy would crush the board's 4GB RAM ceiling during concurrent family backups.

## Tomorrow

Week 01 begins: **Linux & Board Bring-up**. Tomorrow is Day 08 (Week 01 Day 01). We finally connect the USB-to-UART serial bridge to the ROCK 3C's GPIO pins, flash the first Armbian mainline Linux image to our SanDisk Max Endurance microSD card, power up the board for the very first time, and capture our first raw kernel boot logs.
