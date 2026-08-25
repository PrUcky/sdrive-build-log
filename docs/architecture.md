# Architecture

The `sdrive` stack is a self-hosted, end-to-end encrypted photo backup appliance. The architecture is deliberately designed to push all computationally expensive tasks (encryption, machine learning, thumbnail generation) to the mobile client, leaving the server to act as a lightweight, dumb storage router.

## Core Components

1. **Mobile Client (Ente Fork)**
   - Responsible for local encryption.
   - Generates thumbnails, extracts EXIF data, and runs local ML (facial recognition).
   - Never sends plaintext data to the server.

2. **Tailscale (Network Mesh)**
   - Provides a zero-config WireGuard VPN overlay.
   - Allows the mobile client to securely connect to the server from outside the home network without router port forwarding.

3. **Museum (Metadata Server)**
   - The Go backend server from the Ente project.
   - Manages user authentication, folder structures, and sharing permissions.
   - Generates temporary pre-signed S3 URLs so the client can interact with the object store directly.

4. **PostgreSQL (Relational Database)**
   - Stores user accounts, album relationships, and encrypted metadata.
   - Does *not* store the actual photos.

5. **Garage (Object Store)**
   - A lightweight, S3-compatible object store written in Rust.
   - Receives encrypted ciphertext blobs directly from the mobile client via pre-signed URLs.
   - Optimized to run on low-power hardware with slower storage (e.g., SD cards, consumer SSDs).

## Data Flow: Image Upload

1. The user takes a photo.
2. The mobile client locally derives encryption keys and encrypts the raw bytes into a ciphertext blob.
3. The client pings `museum` to declare its intent to upload.
4. `museum` validates the user and replies with a short-lived, pre-signed S3 URL for the `Garage` object store.
5. The client uses the pre-signed URL to upload the heavy, encrypted blob *directly* to `Garage`, completely bypassing `museum`.
6. Once the upload finishes, the client sends the encrypted file metadata (file size, ciphertext hash) to `museum` for safekeeping in `PostgreSQL`.

Because the server never possesses the decryption keys, it is mathematically impossible for anyone who steals the hardware to view the photos.