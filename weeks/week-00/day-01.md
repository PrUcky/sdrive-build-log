# Day 01 — The Machine and the Network

**Week:** 00 · **Date:** 2026-08-19 · **Hours:** 6

## What I Did & Learned
- **Hardware unboxing and component check:** Inspected the Radxa ROCK 3C board, USB-C power supply (5V 3A), heatsink, and MicroSD card. Visually mapped out the Rockchip RK3566 SoC, LPDDR4 RAM, Gigabit Ethernet, USB 3.0 ports, and the M.2 NVMe expansion slot.
- **De-mystifying the "Cloud":** Grounded the mental model that cloud storage is simply someone else's server running in a remote datacenter. sdrive replaces recurring cloud rent by running the server locally on hardware I own.
- **Client vs. Server architecture:** Mapped the boundary between the mobile phone (client generating encrypted photos) and the ROCK 3C appliance (server receiving metadata and ciphertext blobs).
- **Architecture diagrams:** Sketched the packet flow by hand twice to internalize how an upload moves from cellular radio -> cell tower -> ISP -> home router -> local Ethernet -> appliance.

## What Broke & What Confused Me
- **Power supply trap:** Realized standard USB-PD laptop chargers might fail to negotiate high current at 5V without proper protocol chips. Verified my power supply delivers a steady 5V/3A baseline before first boot.
- **Mental hurdle on encryption:** Initially struggled with why the server doesn't need to generate thumbnails or transcode video. Realized that end-to-end encryption forces heavy computation onto the phone, which is why this stack can run on an 8GB board under 1GB of memory.

## Benchmark Answers
1. **Server vs. Laptop:** A server is dedicated to waiting for and answering network requests headless (no display, no battery), optimized for continuous uptime and I/O rather than interactive GUI usage.
2. **The Cloud:** Physical racks of networked commodity computers inside enterprise datacenters.
3. **Roles in sdrive:** The mobile phone is the client; the Radxa ROCK 3C is the server.
4. **Photo upload path:** Phone (cellular) -> Carrier base station -> Internet transit -> Home WAN router -> Switch/LAN -> ROCK 3C storage.
