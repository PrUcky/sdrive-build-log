# Architecture

The `sdrive` stack is a self-hosted, end-to-end encrypted photo backup appliance. The architecture is deliberately designed to invert the traditional cloud model: instead of the server doing all the heavy lifting, we push every computationally expensive task (encryption, machine learning, thumbnail generation, EXIF extraction) to the mobile client. The server acts exclusively as a lightweight, zero-knowledge storage router. 

This architecture allows us to run enterprise-grade privacy on hardware that costs less than a decent dinner, while ensuring mathematically guaranteed security against physical theft.

## 1. The Hardware Layer

- **Board:** Radxa ROCK 3C (RK3566 SoC, 4GB/8GB LPDDR4)
- **Primary Storage (OS & DB):** High-endurance microSD card (for the v1 prototype), migrating to an eMMC module for the v2 production build.
- **Secondary Storage (Blob Storage):** Dedicated NVMe SSD in the M.2 slot (to be added in v2).

*Why this hardware?* Because the server never processes an image or runs an AI model, it doesn't need an NPU or massive CPU headroom. It only needs enough I/O bandwidth to saturate a Gigabit home network connection when saving encrypted blobs to disk.

## 2. The Network Layer

- **Mesh Overlay:** Tailscale (WireGuard-based)
- **Topology:** Peer-to-Peer (P2P)

*Why this network?* To act as a true cloud replacement, the appliance must be accessible from anywhere in the world (cellular data, coffee shop Wi-Fi). However, traditional port forwarding exposes the server to the public internet and is often blocked by Carrier-Grade NAT (CGNAT). Tailscale provides a zero-configuration, secure mesh overlay that easily punches through NAT, ensuring the mobile client can always reach the server securely without exposing it to malicious scanners.

## 3. The Core Software Components

### The Mobile Client (Ente Fork)
The client is the brain of the entire operation. It is responsible for:
- **Local Machine Learning:** Running on-device facial recognition and object detection before encryption.
- **Metadata Extraction:** Pulling GPS and EXIF data from the raw images.
- **Transcoding & Thumbnailing:** Generating compressed previews.
- **Encryption:** Deriving a local key from the user's master password (using Argon2) and encrypting every byte of data (both metadata and the raw file) using XChaCha20-Poly1305 before it ever leaves the phone.

### Museum (The Metadata Server)
Written in Go, `museum` is the internal backend API. 
- **Role:** It acts as the bouncer and the librarian. 
- **Function:** It handles user authentication, maintains the folder/album hierarchy, and manages sharing permissions. 
- **Zero-Knowledge:** It never sees a raw photo. It only stores the relationships between encrypted file IDs.

### PostgreSQL (The Relational Database)
- **Role:** The memory of the metadata server.
- **Function:** Stores the encrypted metadata, user accounts, and album structures. 
- **Storage:** Lives on the primary OS drive (microSD / eMMC).

### Garage (The Object Store)
- **Role:** The dumb bucket where the heavy lifting goes.
- **Function:** A lightweight, S3-compatible distributed object store written in Rust. 
- **Storage:** Stores the massive, encrypted ciphertext blobs pushed by the client.

## 4. The Data Flow: Ingestion Loop

The most critical architectural decision is how data moves from the phone to the disk. To prevent the Go server (`museum`) from bottlenecking on low-power hardware, it does not handle the actual file transfers.

1. **Capture & Process:** The user takes a photo. The mobile client runs local ML and generates a thumbnail.
2. **Local Encryption:** The client encrypts the thumbnail, the raw image, and the extracted metadata using the local derived key.
3. **Intent to Upload:** The client sends an API request to `museum` over the Tailscale network: *"I have a 12MB encrypted blob to upload."*
4. **Pre-signed Authorization:** `museum` validates the user's session and generates a temporary, short-lived "pre-signed URL" for the `Garage` S3 bucket.
5. **Direct Client Upload:** The mobile client uses the pre-signed URL to upload the 12MB encrypted blob *directly* into `Garage` via HTTP PUT, completely bypassing `museum`. 
6. **Confirmation & Indexing:** Once `Garage` confirms receipt, the client sends the encrypted metadata (the file size, the ciphertext hash, and the album ID) to `museum`.
7. **Storage:** `museum` commits the relationship to `PostgreSQL`.

By offloading the heavy network transfer directly to the S3 bucket, `museum` is free to handle hundreds of concurrent metadata requests without locking up the CPU, allowing the entire stack to run comfortably on a low-end ARM processor.