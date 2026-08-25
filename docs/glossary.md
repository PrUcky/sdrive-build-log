# Glossary

This is a living document of technical terms, acronyms, and concepts encountered while building the `sdrive` appliance. I am writing these definitions in my own words to ensure I actually understand the underlying mechanics, rather than just copying from Wikipedia.

### B
- **Blob (Binary Large Object):** When we talk about "blobs," we are talking about the actual encrypted photo or video files. A blob is just a massive chunk of binary data that a database doesn't try to understand. The object store (Garage) just takes the blob and drops it on the disk.

### C
- **CGNAT (Carrier-Grade NAT):** A nightmare created by ISPs because the world ran out of IPv4 addresses. Instead of giving your home router a unique public IP address, the ISP puts your router behind *another* router. This makes it literally impossible to forward a port and expose a server to the internet directly. It's the primary reason we are forced to use a mesh VPN like Tailscale.

### E
- **E2EE (End-to-End Encryption):** The foundational pillar of `sdrive`. It means the data is encrypted on the sender's device (the phone) and can only be decrypted by the receiver's device (also the phone). The server that sits in the middle (the ROCK 3C) only ever sees scrambled math. If the server is stolen, the data is useless without the user's master password.

### G
- **Garage:** An incredibly lightweight, S3-compatible distributed object store written in the Rust programming language. While MinIO is the industry standard for this, MinIO is built for massive enterprise servers and will aggressively consume RAM. Garage is built to run on literal potatoes, making it perfect for our low-power ARM board.

### M
- **Museum:** The internal code name for the Go-based backend API server developed by the Ente project. It acts as the traffic cop — it verifies who you are and where your files belong, but it never actually touches the files themselves.

### P
- **PostgreSQL:** The relational database used by `museum`. It doesn't store the photos; it stores the *labels* for the photos. It remembers that User A owns Album B, and Album B contains File ID 123.
- **Pre-signed URL:** A brilliant trick for saving server CPU. Instead of the phone uploading a 50MB video to the Go server (which then has to turn around and upload it to the object store), the Go server gives the phone a temporary "VIP pass" (the pre-signed URL). The phone then uses that pass to upload the video *directly* to the object store. 

### S
- **SBC (Single Board Computer):** A complete, functioning computer built entirely on a single printed circuit board. Unlike a desktop PC where you plug in a motherboard, CPU, and RAM separately, an SBC has everything soldered together. Examples include the Raspberry Pi and our Radxa ROCK 3C.

### T
- **Tailscale:** A zero-configuration mesh VPN built on top of the WireGuard protocol. It creates a private, encrypted network over the public internet, allowing the mobile phone to securely connect to the `sdrive` server as if they were on the same home Wi-Fi network, regardless of physical location.