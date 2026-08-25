# Day 06 — Whiteboards and Cardboard

**Week:** 00 · **Date:** 2026-08-25 · **Hours:** ~5.0

I took a deliberate twenty-four-hour break yesterday. After spending five consecutive days wrestling with cryptographic state machines, network address translation, and storage daemon internals, my brain was completely fried. Stepping away from the screen on August 24th was the best decision I could have made—it gave all those disparate concepts time to settle and synthesize. Today, I came back to the project with total mental clarity for the final orientation milestone: proving I understand the entire system from memory before touching a single piece of hardware.

## What I actually did

The roadmap set a strict exit criterion for Day 06: draw the complete system architecture from memory twice, without referencing a single note, browser tab, or diagram. 

I closed my laptop, walked over to the magnetic whiteboard in my home office, uncapped a black dry-erase marker, and began sketching the topology. 

It felt like a simple exercise at first, but five minutes in, the drawing brutally exposed a lingering flaw in my mental model. On my first sketch, I drew an arrow from the mobile phone pointing to the Go API server (`museum`), and then drew another arrow from `museum` pointing into the storage engine (`Garage`). In my head, I was still instinctively treating the application server as a central funnel that ingests the data and writes it to disk.

I stopped with my marker hovering in mid-air. As I stared at the diagram, the realization from ADR 0004 hit me: `museum` cannot act as a proxy. If every 20MB raw photo payload had to stream through the Go runtime memory, the RK3566's CPU would spike, garbage collection pauses would stall concurrent requests, and the board would choke during bulk uploads. 

I wiped the entire whiteboard completely clean with an eraser and started over from scratch. 

On the second drawing, I got the sequence right:
1. The mobile client pings `museum` over the encrypted Tailscale mesh strictly to request an upload intent token.
2. `museum` authenticates the user via PostgreSQL and returns a cryptographic, time-limited **pre-signed S3 PUT URL**.
3. The mobile client opens a direct HTTP stream to the `Garage` object storage daemon, uploading the encrypted ciphertext blob directly to local flash storage, completely bypassing `museum`.
4. Only after `Garage` confirms disk write does the client notify `museum` to commit the encrypted metadata record into PostgreSQL.

Seeing the clean out-of-band separation between the **control plane** (`museum` + PostgreSQL) and the **data plane** (`Garage` + NVMe/SD) laid out on the whiteboard was the moment the entire architecture crystallized.

I spent the next two hours transcribing that whiteboard session into a comprehensive master document at `docs/architecture.md`. I structured it into four concrete layers: the Physical Hardware Layer (RK3566, LPDDR4, PCIe 2.1 bus), the Network Layer (Tailscale WireGuard mesh, NAT traversal, CGNAT bypass), the Core Software Components, and the detailed seven-step Ingestion Flow. 

I also authored `docs/glossary.md` to establish a living reference for all domain terms—Blob, CGNAT, E2EE, Pre-signed URLs, Single-Board Computers, and Zero-Knowledge proofs—written in conversational, plain-English language with intuitive analogies.

Just as I committed the documentation, the delivery doorbell rang. 

The physical hardware package had arrived. I spent thirty minutes unboxing everything and carefully inventorying the components across my anti-static mat:
- **Radxa ROCK 3C:** The single-board computer itself. It is remarkably tiny—the exact dimensions of a credit card. Seeing the clean black solder mask, the gold-plated M.2 traces on the underside, and the dense surface-mount capacitors surrounding the RK3566 SoC made the project feel suddenly, tangibly real.
- **SanDisk Max Endurance 64GB MicroSD Card:** High-write-cycle flash storage specifically rated for continuous dashcam/security camera writes, which will serve as our prototype boot medium.
- **Aluminum Passive Heatsink:** A grooved anodized black aluminum heatsink with pre-applied 3M thermal adhesive tape to cool the RK3566 under sustained loads.
- **Dedicated 5V/3A Power Supply:** A regulated AC adapter with a heavy-gauge USB-C cable to prevent voltage drop under transient load spikes.

Holding that tiny circuit board in my hand was an almost surreal experience. That single square of fiberglass, consuming less than 3 watts of electricity and sitting silently on my bookshelf, is going to replace a multi-billion dollar hyperscale cloud datacenter for my entire digital photo library. 

I finished the day by publishing a build-in-public update to Twitter/X and drafting our progress notes on Hashnode.

## What confused me

The roadmap had a great behavioral challenge for today: explain the `sdrive` architecture out loud to a non-technical person in three minutes without hesitating. 

I tried explaining the system to my partner over an afternoon cup of coffee. I started off explaining that "the mobile app uses Argon2id key derivation and XChaCha20-Poly1305 symmetric ciphers to push encrypted blobs to an S3-compatible Rust storage daemon via pre-signed URLs." Within thirty seconds, her eyes had completely glazed over. 

I stopped, took a breath, and tried again using a physical analogy:
> *"Imagine you want to park a confidential package in a bank vault. Instead of handing the package to the bank manager (who might peek inside), the bank manager just gives you a one-time, 5-minute VIP keycard to a specific deposit box. You walk directly into the vault, drop the locked box in yourself, lock it with your own secret padlock, and then tell the manager 'it's done.' The bank manager knows a box is parked in spot 42, but has no key, no camera, and no idea what's inside."*

That analogy clicked immediately. Framing pre-signed URLs as "one-time VIP parking passes" is now my go-to mental model for explaining out-of-band object storage to anyone.

## Tomorrow

Tomorrow is Day 07: The Week 00 Retro and Long-Form Article. I will complete `weeks/week-00/retro.md`, write our first comprehensive public technical essay covering the architectural foundation, and mentally prepare for Week 01: Linux Bring-up, serial UART consoles, and flashing our first Armbian kernel image onto the board.
