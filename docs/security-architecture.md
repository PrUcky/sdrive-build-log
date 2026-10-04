# Security Architecture

*Reference: weeks/week-06/day-41.md*

The sdrive appliance employs a "Defense in Depth" strategy. At no point does a single vulnerability or misconfiguration expose user data. We assume the network is hostile, the ISP is snooping, and the local LAN is untrusted.

This document details the 4-layer security perimeter of the stack.

---

## 🛡️ Layer 1: The Tailnet Perimeter (Network Layer)

The appliance exposes **zero TCP ports** to the internet, and only **one UDP port** (41641) to the host interface.

- **WireGuard Cryptography:** The tunnel is secured by Curve25519 (key exchange), ChaCha20 (symmetric encryption), and Poly1305 (MAC).
- **Stealth:** The UDP port drops unauthenticated packets silently. It does not respond to port scans.
- **UFW Lockdown:** A strict host firewall (`scripts/sdrive-firewall.sh`) ensures that even if Docker binds services to `0.0.0.0`, the host drops all packets coming from the physical LAN (`end0`), explicitly requiring traffic to emerge from the `tailscale0` virtual interface.
- **Access Control:** The Tailnet ACL explicitly whitelists which devices (tags) can access the server. 

*If an attacker scans your home IP, they find nothing.*

---

## 🛡️ Layer 2: TLS 1.3 Termination (Transport Layer)

Traffic emerging from the WireGuard tunnel is intercepted by Caddy. 

- **Perfect Forward Secrecy:** Enforced via TLS 1.3 only (or TLS 1.2 with strong AEAD cipher suites).
- **Publicly Trusted Certificates:** A Let's Encrypt certificate is provisioned by Tailscale (DNS-01 challenge), allowing the Ente mobile app to cryptographically verify the server identity and prevent Man-In-The-Middle (MITM) attacks.
- **Strict Headers:** Caddy enforces HSTS (`max-age=31536000`), removes `Server` headers, blocks MIME-sniffing, and drops Clickjacking attempts via `X-Frame-Options`.
- **Memory Safety:** Caddy is written in Go, eliminating entire classes of buffer overflow vulnerabilities present in older C-based proxies.

*If an attacker somehow breaches the Tailnet, they hit a hardened, memory-safe TLS proxy, not the application.*

---

## 🛡️ Layer 3: The Museum API (Application Layer)

Caddy strips the TLS and forwards plaintext HTTP to the Museum backend over the isolated Docker bridge network (`internal`).

- **Authentication:** All API endpoints require a JWT token generated during the SRP (Secure Remote Password) protocol login. 
- **Authorization:** PostgreSQL enforces isolation. The API validates that User A cannot request, modify, or list Object IDs belonging to User B.
- **Zero Public Ports:** Museum has no `ports:` directive in `docker-compose.yml`. It is physically unreachable except via Caddy.

*If an attacker breaches the TLS proxy, they hit a zero-trust API that demands cryptographic proof of identity for every action.*

---

## 🛡️ Layer 4: Client-Side End-to-End Encryption (Data Layer)

This is the ultimate fallback and the core value proposition of the Ente architecture.

- **Zero Knowledge:** The Museum server never sees plaintext photos or videos. 
- **The Protocol:** Before a photo leaves the phone, it is encrypted locally using **XChaCha20-Poly1305**. The encryption key is derived using Argon2id.
- **The Key Bundle:** The file's unique decryption key is encrypted with the user's master key and stored as a separate S3 object.
- **At Rest:** Garage writes Blake2-hashed blocks to the SSD. If a thief steals the physical ROCK 3C or the external SSD, they acquire encrypted blobs of noise.

*If an attacker breaches the Tailnet, breaches the TLS proxy, exploits a zero-day in Museum, and dumps the entire PostgreSQL database and the Garage SSD, they still cannot view a single photo.*

---

## Container Hardening Details

Each container in the stack shares the following runtime constraints (`docker-compose.yml`):

1. **`security_opt: ["no-new-privileges:true"]`**: Processes cannot gain new privileges via `setuid` binaries.
2. **`read_only: true`**: The root filesystem is immutable. If an attacker gains Remote Code Execution (RCE), they cannot download malware, alter binaries, or write backdoors to disk.
3. **`tmpfs`**: Ephemeral in-memory filesystems are mounted over `/tmp` and `/run` for required transient writes.
4. **Memory Limits**: Caddy (256MB), Garage (256MB), Postgres (512MB), Museum (512MB). This prevents one compromised or runaway container from triggering an Out-Of-Memory kernel panic on the host. 
