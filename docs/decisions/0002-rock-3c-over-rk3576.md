# 0002: Radxa ROCK 3C over RK3576 Boards

**Date:** 2026-08-23
**Status:** Accepted

## Context
We need a Single Board Computer (SBC) to act as the server appliance. The current market is flooded with new boards featuring the RK3576 SoC, which boasts massive Neural Processing Unit (NPU) capabilities, DDR5 RAM, and high core clocks designed for local AI processing. The Radxa ROCK 3C, featuring the older RK3566 SoC and LPDDR4, is noticeably less powerful.

## Decision
We are building on the **Radxa ROCK 3C**.

As documented in [ADR 0001](0001-ente-over-immich.md), the choice of Ente means the server does absolutely zero heavy lifting. It does not run machine learning models, it does not transcode video, and it does not index raw images. It only routes encrypted ciphertext and serves a PostgreSQL database of file IDs. 

An RK3576 would sit entirely idle 99% of the time. The RK3566 provides more than enough I/O bandwidth and memory (especially the 4GB/8GB variants) to saturate a Gigabit home network connection when saving blobs to disk, which is our only actual bottleneck.

## Consequences
- **Positive:** Lower total bill of materials (BOM) cost.
- **Positive:** Significantly lower idle and load power draw, meaning less heat and a much easier time designing a fanless or low-noise 3D printed enclosure.
- **Negative:** We lock ourselves out of ever pivoting to a server-side ML stack (like Immich) on this specific hardware revision without terrible performance.