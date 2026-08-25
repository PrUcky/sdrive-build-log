# Day 04 — The Empty House

**Week:** 00 · **Date:** 2026-08-22 · **Hours:** ~4.0

Today was an exercise in deliberate architectural nesting. The hardware arrives early next week, but I was determined that when the physical board finally lands on my desk, the entire software and documentation scaffolding should already be fully erected, organized, and waiting to receive it. Building a complex embedded system across twelve weeks without a structured repository layout is a recipe for organizational chaos.

## What I actually did

I spent the afternoon establishing the full directory layout of the `sdrive-build-log` repository. Up until today, the project was just a loose directory containing the first three daily logs. I sat down and constructed the comprehensive directory hierarchy that will house every artifact generated across the entire 78-day roadmap:

- `docs/`: Master architecture specifications, hardware schematics, and decision records.
- `diagrams/`: Hand-drawn whiteboard photos, Mermaid diagrams, and network topology exports.
- `config/`: Application and system configuration files.
  - `config/garage/`: Storage daemon configurations (replacing MinIO).
- `scripts/`: Automated bash provisioners, systemd unit generators, and backup scripts.
- `benchmarks/`: Raw telemetry logs, power-draw measurements (watts), and network throughput benchmarks.
- `hardware/`: Enclosure CAD models, STEP files, and 3D print slicing profiles.
- `app/`: Source code for the customized Flutter/Dart mobile client.
- `content/`: Drafts for weekly technical retrospectives, articles, and public build-in-public logs.
- `assets/`: High-resolution photographs, oscilloscope captures, and UI screenshots.

The most critical decision made during this scaffolding phase was explicitly creating `config/garage/` instead of `config/minio/`. 

When I first outlined this project on Day 02, I treated MinIO as the obvious, default choice for our S3 object storage backend. MinIO is virtually synonymous with self-hosted S3 in the enterprise world. But after spending last night reading through low-power storage benchmarks and analyzing MinIO’s evolving architectural trajectory, I realized that MinIO is fundamentally the wrong engine for a low-power single-board computer.

MinIO is aggressively optimized for hyper-scale enterprise Kubernetes clusters with multi-gigabit NVMe arrays and abundant server-class ECC memory. When deployed on a single-board computer with constrained RAM and consumer-grade flash storage, MinIO introduces significant operational friction: its Go runtime memory allocation can cause erratic memory spikes, its disk formatting checks are strictly intolerant of slow I/O, and its recent licensing changes have moved away from grassroots self-hosters.

In contrast, **Garage**—an open-source S3-compatible object store developed in Rust by the Deuxfleurs collective—was architected specifically for lightweight, heterogeneous, and geo-distributed self-hosting environments. Garage runs inside a tiny single static binary, maintains a steady-state memory footprint of around 40MB to 60MB, and is engineered to gracefully handle slow, high-latency consumer storage without locking or crashing. Because our mobile client pushes encrypted ciphertext directly to the storage engine via pre-signed URLs, Garage gives us a rock-solid, ultra-efficient S3 endpoint that leaves over 3.5GB of RAM free for the rest of the OS and PostgreSQL.

Once the directory tree was initialized, I authored a comprehensive root `README.md`. I wanted the repository to serve as a transparent, public-facing engineering handbook that documents the 12-week schedule, the hardware bill of materials, the cryptographic architecture, and the project's core philosophy.

Finally, I committed the complete text of the **GNU Affero General Public License version 3 (AGPL-3.0)** to the repository root. Choosing AGPL-3.0 was a very deliberate legal and ethical choice:
- Traditional open-source licenses like MIT or Apache 2.0 allow commercial entities to take open-source codebases, wrap them in proprietary cloud infrastructure, and monetize them as a service without contributing modifications back to the community.
- Standard GPL-3.0 protects software distributed as binaries, but contains a massive loophole: running modified code as a networked software-as-a-service (SaaS) does not trigger the distribution clause.
- **AGPL-3.0 Section 13 (Remote Network Interaction)** explicitly closes this loophole by requiring anyone who modifies the software and operates it over a computer network to make the complete corresponding source code available to all network users free of charge. For an end-to-end encrypted privacy appliance designed to combat centralized cloud monopolies, AGPL-3.0 is the only license that guarantees perpetual openness.

## What confused me

I spent over an hour debating the repository architecture for the mobile application. Should the mobile client live directly inside this repository under `app/` as a monorepo, or should I fork Ente’s client repository separately and link it via a Git submodule?

Git submodules are notoriously brittle during rapid iteration; they require constant manual pointer updates and introduce friction when branching. On the other hand, maintaining a full Flutter client codebase alongside Linux systemd unit files in a single repository creates a mixed codebase. Ultimately, I opted for the monorepo approach for this prototype phase. Having all infrastructure scripts, hardware models, configuration files, and client-side changes synchronized under a single atomic Git commit hash ensures that the documentation and the codebase never drift out of alignment. If the mobile app requires separate continuous integration pipelines in Week 08, we can cleanly extract it into an independent repository.

## Tomorrow

Tomorrow is Day 05: The Decision Records. I will formally author the five foundational Architecture Decision Records (ADRs) in `docs/decisions/`—documenting the rigorous technical rationale for Ente over Immich, ROCK 3C over RK3576, Tailscale before Headscale, Garage over MinIO, and booting from SD cards for the prototype.
