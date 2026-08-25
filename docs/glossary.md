# Glossary

This is a living document of terms and concepts encountered while building `sdrive`.

- **Blob (Binary Large Object):** A collection of binary data stored as a single entity in a database management system. In our case, an encrypted photo file.
- **CGNAT (Carrier-Grade NAT):** A method ISPs use to share a single public IP address among multiple customers. It makes traditional port forwarding impossible, which is why we need a mesh VPN like Tailscale.
- **E2EE (End-to-End Encryption):** A system of communication where only the communicating users can read the messages. In our architecture, the "communicating users" are just the mobile app. The server is treated as an untrusted adversary.
- **Garage:** A lightweight, S3-compatible distributed object store written in Rust. Selected over MinIO for its low memory footprint.
- **Museum:** The internal code name for Ente's Go-based backend server. It handles authentication and metadata, but never touches raw files.
- **Pre-signed URL:** A temporary URL that grants a client direct upload/download access to a specific object in an S3 bucket, bypassing the main application server. This is critical for offloading network bandwidth from the Go backend.
- **SBC (Single Board Computer):** A complete computer built on a single circuit board. Examples include the Raspberry Pi and our Radxa ROCK 3C.
- **Tailscale:** A zero-configuration VPN built on top of WireGuard. It creates a secure mesh network between devices, regardless of where they are in the world.