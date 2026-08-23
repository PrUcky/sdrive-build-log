# 0005: SD Boot for Prototype

**Date:** 2026-08-23
**Status:** Accepted

## Context
The Radxa ROCK 3C offers three primary storage interfaces: a microSD card slot, an eMMC socket, and a single-lane PCIe M.2 slot for NVMe drives. We need to decide where the operating system and the PostgreSQL database will live during the initial build phase.

## Decision
The v1 prototype will boot and run entirely from a **high-endurance microSD card**.

While eMMC is vastly superior for OS durability, and NVMe is vastly superior for database I/O, dealing with flashing eMMC modules or fighting with bootloader support for NVMe introduces friction on Day 1. The goal of Week 1 and Week 2 is establishing the software loop, not fighting hardware constraints.

## Consequences
- **Positive:** Immediate momentum. We can flash an Armbian image to an SD card from a laptop, slot it in, and have a running Linux system in 5 minutes.
- **Negative:** MicroSD cards are notorious for failing under heavy database write loads. 
- **Mitigation:** This is strictly for the prototype phase. Once the software stack is proven, the production build (v2) will separate the concerns: the OS and DB will be moved to an eMMC module for durability, and the actual Garage object storage (the heavy photo blobs) will be routed to a dedicated NVMe drive in the M.2 slot.