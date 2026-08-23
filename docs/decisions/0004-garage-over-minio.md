# 0004: Garage over MinIO

**Date:** 2026-08-23
**Status:** Accepted

## Context
The Ente backend requires an S3-compatible object store to house the encrypted photo blobs. The default industry standard for self-hosted S3 is MinIO. 

However, our architecture relies heavily on pre-signed URLs. The Go server (`museum`) grants a short-lived token to the mobile client, and the client pushes the multi-megabyte ciphertext blob *directly* to the object store. This means the object store is not a quiet, internal backend service — it is a heavily hit, client-facing service.

## Decision
We will use **Garage** instead of MinIO for our object storage backend.

MinIO is an incredible piece of software, but it is aggressively optimized for enterprise data centers. It expects extremely fast NVMe arrays, substantial CPU cache, and gigabytes of RAM. When deployed on a low-power SBC (like our ROCK 3C) with consumer-grade storage, it frequently throws warnings, aggressively consumes memory, and can become unstable.

Garage is a lightweight, distributed object store written in Rust. It was designed specifically to run on heterogeneous, low-power hardware (the "potato" use case). It respects memory limits and handles slow I/O gracefully without crashing.

## Consequences
- **Positive:** A radically smaller memory footprint for the object store, leaving plenty of breathing room for PostgreSQL and Linux page caching.
- **Positive:** The system will not crash or throw I/O warnings when we inevitably bottleneck on the SD card or a cheap SSD during bulk initial uploads.
- **Negative:** We deviate from Ente's default deployment recommendations. We will have to write our own systemd services/Docker composes and handle any edge-case incompatibilities ourselves.